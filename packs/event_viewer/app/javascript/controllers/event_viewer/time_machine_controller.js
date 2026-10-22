import { Controller } from "@hotwired/stimulus"
import { prefersReducedMotion } from "controllers/motion"

// タイムマシン: 「何件目まで足すか」（position）を動かすと、その出来事までの残高・状態・通帳を出す。
// 計算はサーバー（EventViewer::TimeMachine）で済んでいて、通帳の行の data-balance などを読むだけ。
// まだ起きていない行はうすく、いまの行は印をつける。残高の数字は前の値から数える（視差効果を減らす設定ならすぐ）
const STEP_MS = 900

export default class extends Controller {
  static targets = ["balance", "status", "count", "when", "slider", "row", "result", "play"]
  static values = { position: Number }

  disconnect() {
    this.pause()
    cancelAnimationFrame(this.frame)
    clearTimeout(this.settle)
  }

  positionValueChanged(position) {
    if (!this.hasSliderTarget) return

    this.sliderTarget.value = position
    this.rowTargets.forEach((row) => {
      const p = Number(row.dataset.position)
      row.classList.toggle("is-future", p > position)
      row.classList.toggle("is-now", p === position)
    })
    this.element.querySelectorAll(".tm-chip[data-position]").forEach((chip) => {
      chip.classList.toggle("is-future", Number(chip.dataset.position) > position)
    })
    const row = this.rowTargets.find((r) => Number(r.dataset.position) === position)
    this.statusTarget.textContent = row ? row.dataset.status : "未開設"
    this.whenTarget.textContent = row ? row.dataset.when : "はじまる前"
    this.countTarget.textContent = position
    this.countTo(this.balanceAt(position))
    if (row && this.playing) row.scrollIntoView({ block: "nearest", behavior: prefersReducedMotion() ? "auto" : "smooth" })
  }

  scrub() {
    this.pause()
    this.positionValue = Number(this.sliderTarget.value)
  }

  first() { this.pause(); this.positionValue = 0 }
  last() { this.pause(); this.positionValue = this.rowTargets.length }
  back() { this.pause(); this.positionValue = Math.max(0, this.positionValue - 1) }
  forward() { this.pause(); this.positionValue = Math.min(this.rowTargets.length, this.positionValue + 1) }

  // コマ送り: いまが最後なら、はじめから1件ずつ足していく
  toggle() {
    if (this.playing) return this.pause()

    if (this.positionValue >= this.rowTargets.length) this.positionValue = 0
    this.playing = true
    this.playTarget.textContent = "■ 止める"
    this.timer = setInterval(() => {
      if (this.positionValue >= this.rowTargets.length) return this.pause()
      this.positionValue += 1
    }, STEP_MS)
  }

  pause() {
    clearInterval(this.timer)
    this.playing = false
    if (this.hasPlayTarget) this.playTarget.textContent = "▶ コマ送り"
  }

  balanceAt(position) {
    const row = this.rowTargets.find((r) => Number(r.dataset.position) === position)
    return row ? Number(row.dataset.balance) : 0
  }

  countTo(to) {
    const from = this.shown ?? to
    this.shown = to
    this.resultTarget.textContent = to.toLocaleString("ja-JP")
    cancelAnimationFrame(this.frame)
    clearTimeout(this.settle)
    if (from !== to) this.bump(to > from ? "up" : "down")
    if (prefersReducedMotion() || from === to) return this.render(to)

    // 画面が描かれていない（タブが裏にある）と requestAnimationFrame が来ないので、少しあとに必ず最後の値にする
    this.settle = setTimeout(() => {
      cancelAnimationFrame(this.frame)
      this.render(to)
    }, 600)
    const start = performance.now()
    const tick = (now) => {
      const t = Math.min((now - start) / 450, 1)
      this.render(Math.round(from + (to - from) * (1 - Math.pow(1 - t, 3))))
      if (t < 1) this.frame = requestAnimationFrame(tick)
    }
    this.frame = requestAnimationFrame(tick)
  }

  render(n) {
    this.balanceTarget.textContent = `${n.toLocaleString("ja-JP")} ちゅ〜る`
  }

  bump(direction) {
    if (prefersReducedMotion()) return
    this.balanceTarget.classList.remove("up", "down")
    void this.balanceTarget.offsetWidth // アニメーションをやり直すため
    this.balanceTarget.classList.add(direction)
  }
}
