<script type="text/typescript">
    import Tailwindcss from "./Tailwind.svelte";
    import PatternOverview from "./PatternOverview.svelte";
    import { tick } from "svelte";
    import type { SqlJs } from "sql.js/module";
    import { initSQL } from "./db";
    import { getLanguageModel, getTranslations } from "./modelstorage";
    import { SvelteSubject } from "./SvelteSubject";
    import {
        getNextSentenceId,
        getSentence,
        getSentencePatterns,
        saveExcerciseResult,
        getPatternOverview,
    } from "./model";
    import SentenceDiff from "./SentenceDiff.svelte";
    import Diff from "diff";
    import {
        Observable,
        BehaviorSubject,
        ReplaySubject,
        Subject,
        from,
        of,
        combineLatest,
        zip,
        concat,
    } from "rxjs";
    import {
        switchMap,
        withLatestFrom,
        map,
        mergeMap,
        mergeScan,
        startWith,
        share,
    } from "rxjs/operators";
    import { translateSentenceFromDb } from "./translation";
    import { modelPatternToRegExp, getProposedWords } from "./model_utils";

    /* console.log('navigator.language: ', navigator.language); */

    const lang = new ReplaySubject<string>(1);
    const nativeLang = new ReplaySubject<string>(1);
    const available_languages: Array<{
        lang: string;
        translations: Array<string>;
    }> = "AVAILABLE_LANGUAGES"; // will be filled at build time
    const userInput = new SvelteSubject("");
    let showDiff = false;
    let inputField: HTMLInputElement;

    const pressedEnter = new Subject<void>();
    const finishCurrentSentence = new Subject<void>();

    const SQL: Observable<SqlJs.SqlJsStatic> = from(initSQL()).pipe(share());
    const modelDb = combineLatest([SQL, lang]).pipe(
        switchMap(([SQL, lang]) => {
            return from(getLanguageModel(SQL, lang)).pipe(
                map((db) => {
                    console.log("getLanguageModel:", (db as any).filename);
                    return db;
                }),
                mergeMap((initialDb) =>
                    concat(
                        of(initialDb),
                        finishCurrentSentence.pipe(
                            withLatestFrom(matchedPatterns),
                            mergeScan((currentDb, [_, matchedPatterns]) => {
                                userInput.next("");
                                showDiff = false;
                                const nextDb = from(
                                    saveExcerciseResult(
                                        SQL,
                                        currentDb,
                                        lang,
                                        matchedPatterns
                                    )
                                );
                                return nextDb;
                            }, initialDb)
                        )
                    )
                )
            );
        }),
        share()
    );
    const translationDb = combineLatest([SQL, lang, nativeLang]).pipe(
        switchMap(([SQL, lang, nativeLang]) => {
            return from(getTranslations(SQL, lang, nativeLang)).pipe(
                map((db) => {
                    console.log("getTranslations:", (db as any).filename);
                    return db;
                })
            );
        }),
        share()
    );

    SQL.forEach((db) => console.log("SQL: ", db != null));
    modelDb.forEach((db: any) => console.log("modelDb: ", db.filename));
    translationDb.forEach((db: any) =>
        console.log("translationDb: ", db.filename)
    );

    const currentSentenceId: Observable<string> = modelDb.pipe(
        map(getNextSentenceId),
        share()
    );
    const currentSentence: Observable<string> = zip(
        modelDb,
        currentSentenceId
    ).pipe(
        map(([modelDb, sentenceId]) => getSentence(modelDb, sentenceId)),
        share(),
        startWith("")
    );
    const currentPatterns: Observable<Array<string>> = zip(
        modelDb,
        currentSentenceId
    ).pipe(
        map(([modelDb, sentenceId]) =>
            getSentencePatterns(modelDb, sentenceId)
        ),
        share(),
        startWith([])
    );

    const matchedPatterns: Observable<Array<{
        pattern: string;
        matched: boolean;
    }>> = combineLatest([
        userInput,
        zip(currentSentence, currentPatterns),
    ]).pipe(
        map(([userInput, [currentSentence, currentPatterns]]) =>
            currentPatterns.map((pattern) => {
                const regex = modelPatternToRegExp(pattern, currentSentence);
                const matched = regex.test(userInput);
                return { pattern: pattern, matched: matched };
            })
        ),
        share(),
        startWith([])
    );

    const allPatternsMatch: Observable<boolean> = matchedPatterns.pipe(
        map((matchedPatterns) =>
            matchedPatterns.reduce(
                (acc, pattern) => acc && pattern.matched,
                true
            )
        ),
        share(),
        startWith(false)
    );

    const currentTranslations: Observable<Array<string>> = combineLatest([
        translationDb,
        currentSentenceId,
    ]).pipe(
        map(([translationDb, sentenceId]) =>
            translateSentenceFromDb(translationDb, sentenceId)
        ),
        share(),
        startWith([])
    );

    const patternOverview: Observable<Array<{
        pattern: string;
        rank: number;
        proficiency: number;
    }>> = modelDb.pipe(map(getPatternOverview), share(), startWith([]));

    currentSentence.forEach((s) => {
        console.log("currentSentence:", s);
    });
    finishCurrentSentence.forEach(() => {
        console.log("finishCurrentSentence");
    });

    pressedEnter
        .pipe(withLatestFrom(allPatternsMatch))
        .forEach(([_, allPatternsMatch]) => {
            console.log("--------------------------");
            if (showDiff) finishCurrentSentence.next();
            else {
                if (allPatternsMatch) {
                    finishCurrentSentence.next();
                } else {
                    showDiff = true;
                }
            }
        });

    currentSentence.forEach(async (_) => {
        await tick();
        inputField?.focus();
    });

    const diffProgress = combineLatest([userInput, currentSentence]).pipe(
        map(
            ([userInput, currentSentence]) =>
                Diff.diffChars(currentSentence, userInput)
                    .filter((p) => !p.added && !p.removed)
                    .map((p) => p.value.length)
                    .reduce((acc, val) => acc + val, 0) /
                currentSentence.length
        )
    );
    const errorProgress = combineLatest([userInput, currentSentence]).pipe(
        map(([userInput, currentSentence]) =>
            Math.min(
                Diff.diffChars(currentSentence, userInput)
                    .filter((p) => p.added)
                    .map((p) => p.value.length)
                    .reduce((acc, val) => acc + val, 0) /
                    currentSentence.length,
                1.0
            )
        )
    );

    const proposedWords = currentSentence.pipe(
        map(getProposedWords),
        startWith([])
    );
</script>

<style type="text/scss">
</style>

<Tailwindcss />

<svelte:window
    on:keyup={(e) => {
        if (e.key === 'Enter') pressedEnter.next();
    }} />
<main>
    <div class="h-screen flex justify-center">
        <div class="p-10 flex" style="width: 600px; min-width: 300px;">
            <div class="w-full">
            {#if $lang === undefined}
                <h1>Which language do you want to learn?</h1>
                {#each available_languages as l}
                    <button
                        on:click={() => lang.next(l.lang)}
                        class="bg-indigo-500 text-white font-bold rounded py-2 px-4 mr-1">{l.lang}</button>
                {/each}
            {:else if $nativeLang === undefined}
                <div>Selected: <b>{$lang}</b></div>
                <h1>What is your native language?</h1>
                {#each available_languages.find((l) => l.lang == $lang).translations as t}
                    <button
                        on:click={() => nativeLang.next(t)}
                        class="bg-green-500 text-white font-bold rounded py-2 px-4 mr-1">{t}</button>
                {/each}
            {:else}
                {#each $currentTranslations as sentence}
                    <div class="text-2xl">{sentence}</div>
                {/each}
                {#if showDiff}
                    {#if $userInput != ''}
                        <div>{$currentSentence}</div>
                    {/if}
                    <div>
                        <SentenceDiff
                            original={$currentSentence}
                            userInput={$userInput} />
                    </div>
                    <button
                        on:click={() => pressedEnter.next()}
                        class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline">Next</button>
                {:else}
                    <div class="flex">
                        <input
                            bind:value={$userInput}
                            bind:this={inputField}
                            type="text"
                            class="border rounded w-full py-2 px-3 leading-tight outline-none focus:shadow-outline"
                            placeholder="Type {$lang} translation" />
                        <button
                            on:click={() => pressedEnter.next()}
                            class="ml-1 bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline">Check</button>
                    </div>
                {/if}
                {#if !showDiff}
                    <div
                        class="mt-2 h-3 relative max-w-xl rounded-full overflow-hidden">
                        <div class="w-full h-full bg-gray-200 absolute" />
                        <div
                            class="h-full bg-green-500 absolute"
                            style="width:{$diffProgress * 100}%" />
                    </div>
                    <div
                        class="mt-2 h-3 relative max-w-xl rounded-full overflow-hidden">
                        <div class="w-full h-full bg-gray-200 absolute" />
                        <div
                            class="h-full bg-red-500 absolute"
                            style="width:{$errorProgress * 100}%" />
                    </div>
                    {#each $proposedWords as word}
                        <button
                            on:click={async () => {
                                userInput.next(userInput.getValue() + word);
                                await tick();
                                inputField?.focus();
                            }}
                            class="mr-1 mt-2 hover:bg-gray-200 py-2 px-4 border rounded focus:outline-none focus:shadow-outline text-white hover:text-black">{word}</button>
                    {/each}
                {/if}

                <!--
            {#each matchedPatterns as pattern}
                <div style={pattern.matched ? 'color: green' : ''}>
                    {pattern.pattern}
                </div>
            {/each}
            //-->
            {/if}
                </div>
            <PatternOverview data={$patternOverview} />
        </div>
    </div>
</main>
