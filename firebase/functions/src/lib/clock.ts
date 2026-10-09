/** Injectable clock so tests can move time forward (turn timeouts, ghosts). */
export const clock = {
  now: (): number => Date.now(),
};
