import { Controller } from "@hotwired/stimulus"
import { prefersReducedMotion } from "controllers/motion"

// ねこの実況: 実況の係のジョブ（EventViewer::CommentaryJob・MyEvents::CommentaryJob）が配信する Turbo Stream（実況の1行を頭に足す）を
// 横取りして、1行ずつ間をあけて入れ、ねこのセリフ窓にしゃべらせる（window の cat:say。表情は行の data-face）。
// 振込のように出来事が続けて届くときも、前のセリフを読み終わるくらいの間をあける。ためすぎたら間を短くする。
// 利用者の画面では一覧を隠して（hidden）セリフ窓だけ、行員の実況の画面では一覧も見せる
const GAP = 2600 // ミリ秒。1行を読むくらいの間
const SHORT_GAP = 1200 // たまっているときの間
const MAX_ROWS = 50

export default class extends Controller {
  static targets = ["list"]

  connect() {
    this.queue = []
    this.intercept = this.intercept.bind(this)
    document.addEventListener("turbo:before-stream-render", this.intercept)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.intercept)
    clearTimeout(this.timer)
    this.timer = null
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

  drain() {
    if (this.timer || this.queue.length === 0) return

    this.speak(this.queue.shift())
    this.timer = setTimeout(() => {
      this.timer = null
      this.drain()
    }, this.queue.length > 2 ? SHORT_GAP : GAP)
  }

  speak(row) {
    if (!prefersReducedMotion()) {
      row.classList.add("is-arriving")
      row.addEventListener("animationend", () => row.classList.remove("is-arriving"), { once: true })
    }
    this.listTarget.prepend(row)
    while (this.listTarget.children.length > MAX_ROWS) this.listTarget.lastElementChild.remove()

    const { text, face, bounce } = row.dataset
    if (text) window.dispatchEvent(new CustomEvent("cat:say", { detail: { text, face, bounce: bounce === "true" } }))
  }
}
