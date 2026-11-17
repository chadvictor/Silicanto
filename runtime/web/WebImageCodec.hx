import haxe.io.Bytes;

#if (cpp && silicanto_apple_image)
@:buildXml('<target id="haxe"><flag value="-framework"/><flag value="ImageIO"/><flag value="-framework"/><flag value="CoreGraphics"/><flag value="-framework"/><flag value="CoreFoundation"/></target>')
@:cppFileCode('
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
static ::Array<unsigned char> silicantoDecodeJpeg(::Array<unsigned char> source) {
  CFDataRef data=CFDataCreate(kCFAllocatorDefault,reinterpret_cast<const unsigned char*>(source->GetBase()),source->length);
  CGImageSourceRef images=CGImageSourceCreateWithData(data,NULL);CFRelease(data);
  CGImageRef img=images?CGImageSourceCreateImageAtIndex(images,0,NULL):NULL;
  if(images)CFRelease(images);
  if(!img)return null();
  size_t w=CGImageGetWidth(img),h=CGImageGetHeight(img);
  if(!w||!h||w>16777216/h){CGImageRelease(img);return null();}
  ::Array<unsigned char> out=::Array_obj<unsigned char>::__new((int)(8+w*h*4));
  unsigned char* dst=reinterpret_cast<unsigned char*>(out->GetBase());for(int i=0;i<4;i++){dst[i]=(w>>(i*8))&255;dst[4+i]=(h>>(i*8))&255;}
  CGColorSpaceRef cs=CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  CGContextRef ctx=CGBitmapContextCreate(dst+8,w,h,8,w*4,cs,(CGBitmapInfo)kCGImageAlphaNoneSkipLast|(CGBitmapInfo)kCGBitmapByteOrder32Big);
  CGColorSpaceRelease(cs);if(!ctx){CGImageRelease(img);return null();}
  CGContextDrawImage(ctx,CGRectMake(0,0,w,h),img);CGContextRelease(ctx);CGImageRelease(img);
  for(size_t i=0;i<w*h;i++)dst[8+i*4+3]=255;
  return out;
}')
#end
class WebImageCodec {
	// The two little-endian Int32 dimensions precede an opaque RGBA raster.
	public static function jpeg(input:Bytes):Bytes
		return decode(input.getData());

	#if java
	@:functionCode('
    try {
      java.awt.image.BufferedImage img=javax.imageio.ImageIO.read(new java.io.ByteArrayInputStream(data));
      if(img==null)return null;
      int w=img.getWidth(),h=img.getHeight();
      if(w<1||h<1||((long)w)*h>16777216L)return null;
      byte[] out=new byte[8+w*h*4];for(int i=0;i<4;i++){out[i]=(byte)(w>>>(8*i));out[i+4]=(byte)(h>>>(8*i));}
      int[] row=new int[w];int pos=8;
      for(int y=0;y<h;y++){img.getRGB(0,y,w,1,row,0,w);for(int c:row){out[pos++]=(byte)(c>>>16);out[pos++]=(byte)(c>>>8);out[pos++]=(byte)c;out[pos++]=(byte)255;}}
      return haxe.io.Bytes.ofData(out);
    }catch(java.io.IOException ex){return null;}
  ')
	#end
	static function decode(data:haxe.io.BytesData):Bytes {
		#if (cpp && silicanto_apple_image)
		final rgba:haxe.io.BytesData = untyped __cpp__("silicantoDecodeJpeg({0})", data);
		return rgba == null ? null : Bytes.ofData(rgba);
		#else
		return null;
		#end
	}
}
