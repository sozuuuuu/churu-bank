import { Controller } from "@hotwired/stimulus"
import { prefersReducedMotion } from "controllers/motion"

// 生中継: 画面のパックのジョブ（EventViewer::LiveJob・Netbank::EventsLiveJob）が配信する Turbo Stream（一覧の頭に1行足す）を横取りして、
// 1件ずつ間をあけて上から入れる（ふわっと入る動きは CSS の .is-arriving）。
// 「止める」のあいだは届いた行をためておき、「再開」で順に流す。視差効果を減らす設定なら、動かさずにすぐ入れる
const GAP = 900 // ミリ秒。続けて届いたときの間
const MAX_ROWS = 200

export default class extends Controller {
  static targets = ["list", "toggle", "status", "pending", "dot"]
  // say: 利用者の画面では、届いた出来事をねこのセリフ窓でも知らせる（window の cat:say）
  static values = { say: Boolean }

  connect() {
    this.queue = []
    this.paused = false
    this.intercept = this.intercept.bind(this)
    document.addEventListener("turbo:before-stream-render", this.intercept)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.intercept)
    clearTimeout(this.timer)
  }

  intercept(event) {
    const stream = event.target
    if (stream.getAttribute("target") !== this.listTarget.id || stream.getAttribute("action") !== "prepend") return

    event.detail.render = (element) => {
      const row = element.templateContent.firstElementChild
      if (row && !document.getElementById(row.id)) this.queue.push(row)
      this.drain()
    }
  }

  toggle() {
    this.paused = !this.paused
    this.toggleTarget.textContent = this.paused ? "再開する" : "止める"
    this.statusTarget.textContent = this.paused ? "一時停止中" : "生中継中"
    this.element.classList.toggle("is-paused", this.paused)
    this.showPending()
    if (!this.paused) this.drain()
  }

  drain() {
    this.showPending()
    if (this.paused || this.timer || this.queue.length === 0) return

    this.insert(this.queue.shift())
    this.timer = setTimeout(() => {
      this.timer = null
      this.drain()
    }, prefersReducedMotion() ? 0 : GAP)
  }

  insert(row) {
    if (!prefersReducedMotion()) {
      row.classList.add("is-arriving")
      row.addEventListener("animationend", () => row.classList.remove("is-arriving"), { once: true })
      this.dotTarget.classList.remove("is-blink")
      void this.dotTarget.offsetWidth // アニメーションをやり直すため
      this.dotTarget.classList.add("is-blink")
    }
    this.listTarget.prepend(row)
    while (this.listTarget.children.length > MAX_ROWS) this.listTarget.lastElementChild.remove()
    const label = row.querySelector(".ev-row-label")?.textContent
    if (this.sayValue && label) {
      const text = `新しい出来事「${label}」が届いたにゃ。いちばん上に足したにゃ。`
      window.dispatchEvent(new CustomEvent("cat:say", { detail: { text, face: "happy", bounce: true } }))
    }
  }

  showPending() {
    const n = this.queue.length
    this.pendingTarget.hidden = !(this.paused && n > 0)
    this.pendingTarget.textContent = `新しい出来事が ${n} 件たまっています`
  }
}
