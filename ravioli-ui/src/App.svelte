<script type="text/typescript">
    import Tailwindcss from "./Tailwind.svelte";
    import { tick } from "svelte";
    import type { SqlJs } from "sql.js/module";
    import { initSQL } from "./db";
    import { getLanguageModel, saveModel } from "./modelstorage";
    import {
        nextTick,
        nextSentenceId,
        getSentence,
        getSentencePatterns,
        learnedPattern,
    } from "./model";
    import SentenceDiff from "./SentenceDiff.svelte";
    import { translate } from "./translation";
    import Diff from "diff";

    let SQL: SqlJs.SqlJsStatic;
    let db: SqlJs.Database;
    let lang = "fr";

    let currentSentence = "";
    let currentPatterns = [];
    let translatedSentence = "";
    let userInput = "";
    let showDiff = false;
    let inputField: HTMLInputElement;

    $: matchedPatterns = currentPatterns.map((pattern) => {
        let regex = patternToRegExp(pattern);
        let matched = regex.test(userInput);
        return { pattern: pattern, matched: matched };
    });

    $: patternProgress =
        matchedPatterns
            .map((pattern) => (pattern.matched ? 1 : 0))
            .reduce((acc, val) => acc + val, 0) / matchedPatterns.length;

    $: diffProgress =
        Diff.diffChars(currentSentence.replace(/\s*/g, ""), userInput)
            .filter((p) => !p.added && !p.removed)
            .map((p) => p.value.length)
            .reduce((acc, val) => acc + val, 0) /
        currentSentence.replace(/\s*/g, "").length;

    $: errorProgress = Math.min(
        Diff.diffChars(currentSentence, userInput)
            .filter((p) => p.added)
            .map((p) => p.value.length)
            .reduce((acc, val) => acc + val, 0) / currentSentence.length,
        1.0
    );

    $: allPatternsMatch = matchedPatterns.reduce(
        (acc, pattern) => acc && pattern.matched,
        true
    );

    $: proposedWords = (() => {
        let words = currentSentence.replace(/([ \,\!'\-]+)/g, "$1#!#!").split("#!#!").filter(w => w != '');
        shuffleArray(words);
        return words;
    })();

    $: (async () => {
        translatedSentence = await translate(currentSentence, lang, "de");
    })();

    function shuffleArray(array) {
        for (let i = array.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [array[i], array[j]] = [array[j], array[i]];
        }
    }

    async function init() {
        SQL = await initSQL();
        db = await getLanguageModel(SQL, lang);
        showNextSentence();
    }

    async function showNextSentence() {
        let sentenceId = nextSentenceId(db);
        console.log("Next SentenceId:", sentenceId);
        userInput = "";
        translatedSentence = "";
        currentSentence = getSentence(db, sentenceId);
        currentPatterns = getSentencePatterns(db, sentenceId);
        showDiff = false;
        await tick();
        inputField.focus();
    }

    async function finishCurrentSentence() {
        for (var matchedPattern of matchedPatterns) {
            learnedPattern(db, matchedPattern.pattern, matchedPattern.matched);
        }
        nextTick(db);
        db = await saveModel(SQL, db, lang);
        await showNextSentence();
    }

    async function checkAnswer() {
        if (allPatternsMatch) {
            finishCurrentSentence();
        } else {
            showDiff = true;
        }
    }

    function patternToRegExp(pattern: string): RegExp {
        let wildCardRegExp = new RegExp(/\{\*+\}/);
        let patternParts = pattern.split(" ").map((p) => {
            let isWildCard = wildCardRegExp.test(p);
            return isWildCard ? ".*" : regExpEscape(p);
        });
        let regex = new RegExp(patternParts.join("(\\s*)"));

        // only put spaces in the regex, if they are spaces in the real sentence.
        let matches = currentSentence.match(regex);

        const result = patternParts
            .map(
                (p, i) =>
                    p + (i == patternParts.length - 1 ? "" : matches[1 + i])
            )
            .join("");

        // don't care about spaces before punctuation: TODO: Hey Mr. Dog.
        const punctuationAdjustedResult = result.replace(/\s*(\\\?|\\\.|!)$/, '\\s*$1');
        return new RegExp(punctuationAdjustedResult);
    }

    function regExpEscape(string: string): string {
        return string.replace(/[-\/\\^$*+?.()|[\]{}]/g, "\\$&");
    }

    function pressedEnter() {
        if (showDiff) finishCurrentSentence();
        else checkAnswer();
    }

    init();
</script>

<style type="text/scss">
</style>

<Tailwindcss />

<svelte:window
    on:keyup={(e) => {
        if (e.key === 'Enter') pressedEnter();
    }} />
<main>
    <div class="h-screen flex justify-center">
        <div class="p-10">
            <div class="text-2xl">{translatedSentence}</div>
            {#if showDiff}
                {#if userInput != ''}
                    <div>{currentSentence}</div>
                {/if}
                <div>
                    <SentenceDiff original={currentSentence} {userInput} />
                </div>
                <button
                    on:click={finishCurrentSentence}
                    class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline">Next</button>
            {:else}
                <div class="flex">
                    <input
                        bind:value={userInput}
                        bind:this={inputField}
                        type="text"
                        class="border rounded w-full py-2 px-3 leading-tight outline-none focus:shadow-outline"
                        placeholder="Type {lang} translation" />
                    <button
                        on:click={checkAnswer}
                        class="ml-1 bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded focus:outline-none focus:shadow-outline">Check</button>
                </div>
            {/if}
            <div
                class="mt-2 h-3 relative max-w-xl rounded-full overflow-hidden">
                <div class="w-full h-full bg-gray-200 absolute" />
                <div
                    class="h-full bg-green-500 absolute"
                    style="width:{diffProgress * 100}%" />
            </div>
            <div
                class="mt-2 h-3 relative max-w-xl rounded-full overflow-hidden">
                <div class="w-full h-full bg-gray-200 absolute" />
                <div
                    class="h-full bg-red-500 absolute"
                    style="width:{errorProgress * 100}%" />
            </div>
            {#each proposedWords as word}
                <button
                    on:click={() => (userInput += word)}
                    class="ml-1 mt-2 hover:bg-gray-200 py-2 px-4 border rounded focus:outline-none focus:shadow-outline">{word}</button>
            {/each}
            <!--
            {#each matchedPatterns as pattern}
                <div style={pattern.matched ? 'color: green' : ''}>
                    {pattern.pattern}
                </div>
            {/each}
            //-->
        </div>
    </div>
</main>
