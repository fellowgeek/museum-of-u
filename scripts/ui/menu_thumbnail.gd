extends RefCounted
## Encode and decode bounded visit previews.
const SIZE := Vector2i(320,180)
const MAX_ENCODED := 180000

static func encode(image: Image) -> String:
	if image==null or image.is_empty(): return ""
	image.resize(SIZE.x,SIZE.y,Image.INTERPOLATE_LANCZOS)
	return Marshalls.raw_to_base64(image.save_jpg_to_buffer(0.8))

static func texture(encoded: String) -> Texture2D:
	if encoded.is_empty() or encoded.length()>MAX_ENCODED: return null
	var image:=Image.new()
	if image.load_jpg_from_buffer(Marshalls.base64_to_raw(encoded))!=OK: return null
	if image.get_size()!=SIZE: return null
	return ImageTexture.create_from_image(image)
