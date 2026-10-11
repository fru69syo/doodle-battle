/**
 * Fixed-rate loop for the 10 Hz battle tick.
 *
 * setInterval drifts and Node can be busy, so we schedule against the wall clock: if we are
 * late we run the missed ticks immediately (up to `maxCatchUp`), so a match's 3 minutes stay 3
 * minutes. How late we were is reported as tick lag (log-based metric realtime/tick_lag_ms).
 */
export class TickLoop {
  private timer: NodeJS.Timeout | null = null;
  private next = 0;

  constructor(
    private readonly tickMs: number,
    private readonly onTick: () => void,
    private readonly onLag: (ms: number) => void = () => {},
    private readonly maxCatchUp = 5,
    private readonly now: () => number = () => performance.now(),
  ) {}

  start(): void {
    if (this.timer) return;
    this.next = this.now() + this.tickMs;
    this.schedule();
  }

  stop(): void {
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }

  get running(): boolean {
    return this.timer !== null;
  }

  private schedule(): void {
    const delay = Math.max(0, this.next - this.now());
    this.timer = setTimeout(() => { this.fire(); }, delay);
  }

  private fire(): void {
    const late = this.now() - this.next;
    this.onLag(Math.max(0, late));
    let ran = 0;
    while (this.now() >= this.next && ran < this.maxCatchUp) {
      this.onTick();
      this.next += this.tickMs;
      ran++;
    }
    // Too far behind (e.g. the instance was CPU-throttled): skip ahead instead of bursting.
    if (this.now() >= this.next) this.next = this.now() + this.tickMs;
    if (this.timer) this.schedule();
  }
}
