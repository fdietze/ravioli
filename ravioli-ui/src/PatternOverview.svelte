<script type="text/typescript">
    export let data: Array<{
        pattern: string;
        rank: number;
        proficiency: number;
    }> = [];
</script>

<main
    class="h-full w-full flex flex-col bg-gray-800 border-4 rounded border-gray-900">
    {#each data as pattern (pattern.rank)}
        <div
            title={pattern.pattern}
            class="h-full"
            class:bg-green-500={pattern.proficiency > 0}
            class:bg-red-500={pattern.proficiency < 0}
            class:bg-opacity-0={pattern.proficiency == 0}
            class:bg-opacity-25={Math.abs(pattern.proficiency) == 1}
            class:bg-opacity-50={Math.abs(pattern.proficiency) == 2}
            class:bg-opacity-75={Math.abs(pattern.proficiency) == 3}
            class:bg-opacity-100={Math.abs(pattern.proficiency) > 3} />
    {/each}
</main>
