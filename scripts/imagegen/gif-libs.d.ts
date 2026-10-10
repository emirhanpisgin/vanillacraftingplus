declare module "gifenc" {
    export function GIFEncoder(): {
        writeFrame(index: Uint8Array, width: number, height: number, options?: Record<string, unknown>): void;
        finish(): void;
        bytes(): Uint8Array;
    };
    export function quantize(data: Uint8Array | Uint8ClampedArray, maxColors: number): number[][];
    export function applyPalette(data: Uint8Array | Uint8ClampedArray, palette: number[][]): Uint8Array;
}

declare module "gifuct-js" {
    export function parseGIF(data: ArrayBuffer): unknown;
    export function decompressFrames(
        gif: unknown,
        buildImagePatches: boolean,
    ): Array<{ dims: { top: number; left: number; width: number; height: number }; patch: Uint8ClampedArray }>;
}
