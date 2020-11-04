<script type="text/typescript">
    import Diff from "diff";

    export let original: string = "";
    export let userInput: string = "";

    $: diff = Diff.diffChars(original, userInput);
</script>

<style type="text/scss">
</style>

<main>
    {#each diff as part}<span style={part.added ? "color:red; text-decoration: line-through" : part.removed ? "color: gray;" : "color: green"}>{part.value}</span>{/each}
</main>
