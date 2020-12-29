<script type="text/typescript">
    import Diff from "diff";

    export let original: string = "";
    export let userInput: string = "";

    $: diff = Diff.diffChars(original, userInput);
</script>

<style type="text/scss">
</style>

<main>
    {#each diff as part}
        <span
            style={part.added ? 'color:tomato;' : part.removed ? 'color: silver; border: 1px solid silver; border-radius: 2px;' : 'color: forestgreen'}>{part.value}</span>
    {/each}
</main>
