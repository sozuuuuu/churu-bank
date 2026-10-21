import { Controller } from "@hotwired/stimulus"

// ねこの吹き出し（packs/notices の notices/inbox/_board）。
// 新しいお知らせが refresh（morph）で入ってきたら、ねこが跳ねて、トーストで知らせる。
// 吹き出しが「ぽよん」と出るのは CSS（morph で新しく入った要素だけアニメーションが動く）。
// 「視差効果を減らす」設定なら跳ねない（トーストは出す）
export default class extends Controller {
  static targets = ["cat"]

  connect() {
    this.seen = new Set(this.#ids())
    this.observer = new MutationObserver(() => this.#check())
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer.disconnect()
    clearTimeout(this.toastTimer)
  }

  #ids() {
    return [...this.element.querySelectorAll("[data-notice-id]")].map((el) => el.dataset.noticeId)
  }

  #check() {
    const fresh = this.#ids().filter((id) => !this.seen.has(id))
    if (fresh.length === 0) return
    fresh.forEach((id) => this.seen.add(id))

    this.#toast("銀行からお知らせが届いたにゃ！")
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    this.catTargets.forEach((wrap) => {
      const cat = wrap.querySelector(".cat")
      cat.classList.remove("happy")
      void cat.getBoundingClientRect()
      cat.classList.add("happy")
    })
  }

  #toast(message) {
    const toast = document.getElementById("notice-toast")
    if (!toast) return
    toast.textContent = message
    toast.classList.add("show")
    clearTimeout(this.toastTimer)
    this.toastTimer = setTimeout(() => toast.classList.remove("show"), 3000)
  }
}
