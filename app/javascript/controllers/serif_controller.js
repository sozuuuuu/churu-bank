import { Controller } from "@hotwired/stimulus"
import { kira, prefersReducedMotion } from "controllers/motion"

// ねこのセリフ窓（packs/ui の ui/_serif）。セリフを1文字ずつ出し、ねこの表情（data-face）を切り替える。
//   - ページのセリフは data-serif-text-value / face-value（サーバーが cat_says で決める）
//   - 出来事は window の cat:say（detail: { text, face, bounce }）で入れ替える。cat:reset でページのセリフに戻す
//   - 窓をクリックすると、出しかけの文字を全部出す
//   - Turbo の refresh（morph）でページのセリフ（data 属性）が変わればそれを出す。出来事のセリフを出しているあいだは
//     cat:reset まで出さず、morph でも文字とねこは書き換えさせない（keep）
// 「視差効果を減らす」設定なら、1文字ずつにはせず全文を出し、ねこも弾ませない
export default class extends Controller {
  static targets = ["text", "live", "cat"]
  static values = { text: String, face: { type: String, default: "normal" }, speed: { type: Number, default: 40 } }

  disconnect() {
    clearTimeout(this.timer)
  }

  // ページのセリフが変わった（ページを開いた・morph）。出来事のセリフを出しているあいだは、cat:reset まで待つ
  textValueChanged(text) {
    if (!this.spoken) this.#show(text, this.faceValue)
  }

  faceValueChanged(face) {
    if (!this.spoken) this.#setFace(face)
  }

  say({ detail: { text, face = "normal", bounce = false } }) {
    this.spoken = true
    const changed = this.#show(text, face)
    // うれしい顔に変わったときは #setFace が弾ませる。もともとうれしい顔なら、ここで弾む
    if (bounce && !(changed && face === "happy")) this.#bounce()
  }

  // 出来事のセリフを出しているあいだは、morph で文字とねこを書き換えない（窓の data 属性 = ページのセリフは更新させる）
  keep(event) {
    if (!this.spoken) return
    const parts = [this.hasTextTarget && this.textTarget, this.hasLiveTarget && this.liveTarget, this.hasCatTarget && this.catTarget]
    if (parts.includes(event.target)) event.preventDefault()
  }

  reset() {
    this.spoken = false
    this.#show(this.textValue, this.faceValue)
  }

  skip() {
    if (this.typing === undefined) return
    clearTimeout(this.timer)
    this.#finish(this.typing)
  }

  // 表情が変わったら true
  #show(text, face) {
    if (!this.hasTextTarget) return false
    const changed = this.#setFace(face)
    this.liveTarget.textContent = text
    clearTimeout(this.timer)
    this.element.classList.remove("is-done")

    if (prefersReducedMotion() || text.length === 0) {
      this.#finish(text)
      return changed
    }

    this.typing = text
    const chars = Array.from(text)
    let shown = 0
    const tick = () => {
      shown += 1
      this.textTarget.textContent = chars.slice(0, shown).join("")
      if (shown < chars.length) this.timer = setTimeout(tick, this.speedValue)
      else this.#finish(text)
    }
    this.textTarget.textContent = ""
    this.timer = setTimeout(tick, this.speedValue)
    return changed
  }

  #finish(text) {
    this.typing = undefined
    this.textTarget.textContent = text
    this.element.classList.add("is-done")
  }

  // 表情を変える。最初の1回（ページを開いたとき）は動かさず、そのあと変わったときだけ小さく動く
  #setFace(face) {
    if (!this.hasCatTarget || this.face === face) return false
    const first = this.face === undefined
    this.face = face
    const cat = this.catTarget
    cat.dataset.face = face
    cat.setAttribute("aria-label", `ねこのちゅーる（${FACE_LABELS[face] ?? ""}）`)
    if (first) return false
    if (face === "happy") this.#bounce()
    if (face === "surprised") this.#replay("jolt")
    if (face === "sad") this.#replay("droop")
    return true
  }

  // うれしいとき: 弾む（つぶれて伸びる）とキラッ
  #bounce() {
    if (!this.hasCatTarget || prefersReducedMotion()) return
    this.#replay("bounce")
    kira(this.catTarget)
  }

  #replay(name) {
    if (prefersReducedMotion()) return
    const cat = this.catTarget
    cat.classList.remove("bounce", "jolt", "droop")
    void cat.getBoundingClientRect() // アニメーションをやり直すため
    cat.classList.add(name)
    cat.addEventListener("animationend", () => cat.classList.remove(name), { once: true })
  }
}

const FACE_LABELS = { normal: "ふつう", happy: "うれしい", surprised: "びっくり", sad: "しょんぼり" }
