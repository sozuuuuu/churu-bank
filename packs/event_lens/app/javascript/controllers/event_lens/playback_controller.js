import { Controller } from "@hotwired/stimulus"
import { prefersReducedMotion } from "controllers/motion"

// つながりの図・レーン図の「再生」: data-step の番号（書かれた順）に、出来事と矢印を1つずつ光らせる。
// 再生中は図全体をうすくして（.is-playing）、光ったもの（.is-lit）だけをはっきり見せる。終わったら全部もとに戻す。
// 視差効果を減らす設定でもコマ送りはする（光り方の動きは CSS で止める）
const STEP_MS = 800

export default class extends Controller {
  static targets = ["button", "caption"]

  connect() {
    this.idle = this.captionTarget.textContent
    // 図が横にはみ出すときは、選んだ出来事が見えるところまで横に送っておく
    const seed = this.element.querySelector(".is-seed")
    const scroller = this.element.querySelector(".ev-diagram-scroll")
    if (seed && scroller) {
      const left = seed.getBoundingClientRect().left - scroller.getBoundingClientRect().left
      scroller.scrollLeft = Math.max(0, left - scroller.clientWidth / 3)
    }
  }

  disconnect() {
    this.stop()
  }

  toggle() {
    this.playing ? this.stop() : this.play()
  }

  play() {
    const steps = [...new Set(this.items().map((el) => Number(el.dataset.step)))].sort((a, b) => a - b)
    this.playing = true
    this.element.classList.add("is-playing")
    this.items().forEach((el) => el.classList.remove("is-lit", "is-now"))
    this.buttonTarget.textContent = "■ 停止"
    let i = 0
    const next = () => {
      if (i >= steps.length) {
        this.timer = setTimeout(() => this.stop(), STEP_MS * 1.5)
        return
      }
      const step = steps[i++]
      this.items().forEach((el) => el.classList.remove("is-now"))
      this.items(step).forEach((el) => el.classList.add("is-lit", "is-now"))
      const node = this.items(step).find((el) => el.dataset.label)
      if (node) this.captionTarget.textContent = `${i} / ${steps.length}　${node.dataset.label}`
      this.timer = setTimeout(next, prefersReducedMotion() ? STEP_MS * 1.5 : STEP_MS)
    }
    next()
  }

  stop() {
    clearTimeout(this.timer)
    this.playing = false
    this.element.classList.remove("is-playing")
    this.items().forEach((el) => el.classList.remove("is-lit", "is-now"))
    if (this.hasButtonTarget) this.buttonTarget.textContent = "▶ 再生"
    if (this.hasCaptionTarget) this.captionTarget.textContent = this.idle
  }

  items(step) {
    const selector = step === undefined ? "[data-step]" : `[data-step="${step}"]`
    return [...this.element.querySelectorAll(selector)]
  }
}
