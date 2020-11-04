<script type="text/typescript">
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
    import SenteceDiff from "./SenteceDiff.svelte";

    let SQL: SqlJs.SqlJsStatic;
    let db: SqlJs.Database;
    let lang = "fr";

    let currentSentence = "";
    let currentPatterns = [];
    let userInput = "";
    let showDiff = false;
    let inputField;

    $: matchedPatterns = currentPatterns.map((pattern) => {
        let regex = patternToRegExp(pattern);
        let matched = regex.test(userInput);
        return { pattern: pattern, matched: matched };
    });

    async function init() {
        SQL = await initSQL();
        db = await getLanguageModel(SQL, lang);
        showNextSentence();
    }

    async function showNextSentence() {
        let sentenceId = nextSentenceId(db);
        userInput = "";
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
        if (userInput == currentSentence) {
            finishCurrentSentence();
        } else {
            showDiff = true;
        }
    }

    function patternToRegExp(pattern: string): RegExp {
        let wildCardRegExp = new RegExp(/\{\*+\}/);
        return new RegExp(
            pattern
                .split(" ")
                .map((p) => {
                    let isWildCard = wildCardRegExp.test(p);
                    return isWildCard ? ".*" : regExpEscape(p);
                })
                .join("\\s*")
        );
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

<svelte:window
    on:keyup={(e) => {
        if (e.key === 'Enter') pressedEnter();
    }} />
<main>
    <h1>{currentSentence}</h1>
    {#if showDiff}
        <SenteceDiff original={currentSentence} {userInput} />
        <button on:click={finishCurrentSentence}>Next</button>
    {:else}
        <input bind:value={userInput} bind:this={inputField} type="text" />
        <button on:click={checkAnswer}>Check</button>
    {/if}
    {#each matchedPatterns as pattern}
        <div style={pattern.matched ? 'color: green' : ''}>
            {pattern.pattern}
        </div>
    {/each}
</main>
