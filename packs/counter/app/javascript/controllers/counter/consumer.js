import { createConsumer } from "@rails/actioncable"

// 窓口（整理券とチャット）用の Action Cable の接続。ページに1つだけ作り、チャンネルの購読はこれにぶら下げる。
// 接続そのものは最初に購読したときに張られる（ほかの画面ではつながない）。
// 接続の持ち主（行員か利用者か）は Cookie で決まる（ルートの ApplicationCable::Connection）
export default createConsumer()
