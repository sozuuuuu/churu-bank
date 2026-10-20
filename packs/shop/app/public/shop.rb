# ちゅ〜る商店（商品・在庫・注文）の名前空間。画面やほかのパックは Shop::Store を通してだけ操作する。
module Shop
  class Error < StandardError; end

  class NotFound < Error; end
  class NotOpen < Error; end
  class AlreadyListed < Error; end
  class AlreadyPlaced < Error; end
  class InvalidState < Error; end
  class OutOfStock < Error; end

  # 同じ注文・商品に同時に書き込もうとして、後から来た方が負けたとき
  class ConcurrentModification < Error; end
end
