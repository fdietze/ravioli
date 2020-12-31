<script type="text/typescript">
    import { classes } from "./classes";
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
            use:classes={{ 'bg-green-500': pattern.proficiency > 0, 'bg-red-500': pattern.proficiency < 0, 'bg-opacity-0': pattern.proficiency == 0, 'bg-opacity-25': Math.abs(pattern.proficiency) == 1, 'bg-opacity-50': Math.abs(pattern.proficiency) == 2, 'bg-opacity-75': Math.abs(pattern.proficiency) == 3, 'bg-opacity-100': Math.abs(pattern.proficiency) > 3 }}
            class="h-full" />
    {/each}
</main>
