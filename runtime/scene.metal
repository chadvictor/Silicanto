#include <metal_stdlib>
using namespace metal;

struct SceneVertex { float4 pointRoughness, normalMetalness, albedoSide, emissionFog; };
struct CameraFrame {float4 eye, right, up, back, projection;};
struct SceneVaryings {
    float4 position [[position]];
    float3 world, normal, albedo, emission;
    float roughness, metalness, side, fog, distance;
};
struct Lighting {float4 fog, hemiDir, hemiSky, hemiGround, lights[8], probe;};
struct ShadedPixel {float4 value [[color(0),raster_order_group(0)]];};

vertex SceneVaryings sceneVertex(uint id [[vertex_id]], device const SceneVertex *vertices [[buffer(0)]],
                                 constant CameraFrame &c [[buffer(1)]]) {
    SceneVertex v=vertices[id];
    SceneVaryings o;
    o.world=v.pointRoughness.xyz;
    float3 p=o.world-c.eye.xyz;
    float z=dot(p,c.back.xyz);
    o.position=float4(dot(p,c.right.xyz)*c.projection.x,dot(p,c.up.xyz)*c.projection.y,z*c.projection.z+c.projection.w,-z);
    o.normal=v.normalMetalness.xyz; o.metalness=v.normalMetalness.w;
    o.albedo=v.albedoSide.rgb; o.side=v.albedoSide.w;
    o.emission=v.emissionFog.rgb; o.fog=v.emissionFog.w;
    o.roughness=v.pointRoughness.w; o.distance=-z;
    return o;
}

float3 displaySRGB(float3 c) {
    c=max(c,0.0);
    return select(1.055*pow(c,float3(1.0/2.4))-0.055,12.92*c,c<=0.0031308);
}

// Cube-UV layout and split-sum response follow the Three.js r180 shader convention (MIT).
float3 probeLevel(device const float4 *atlas, float4 info, float3 d, float mip) {
    float3 a=abs(d);
    uint face; float2 uv;
    if(a.x>a.z && a.x>a.y) {
        face=d.x>0?0:3; uv=float2(d.x>0?d.z:-d.z,d.y)/a.x;
    } else if(a.z>=a.x && a.z>a.y) {
        face=d.z>0?2:5; uv=float2(d.z>0?-d.x:d.x,d.y)/a.z;
    } else {
        face=d.y>0?1:4; uv=float2(-d.x,d.y>0?-d.z:d.z)/a.y;
    }
    float size=exp2(max(4.0,mip)), highest=exp2(info.z);
    float2 texel=(uv*0.5+0.5)*(size-2)+0.5;
    texel+=float2((face%3)*size+max(4.0-mip,0.0)*48.0,4*(highest-size)+(face>=3?size:0.0));
    uint2 p=uint2(texel); uint stride=uint(info.x), i=p.y*stride+p.x;
    float2 t=fract(texel);
    return mix(mix(atlas[i].rgb,atlas[i+1].rgb,t.x),mix(atlas[i+stride].rgb,atlas[i+stride+1].rgb,t.x),t.y);
}

float3 environment(device const float4 *atlas, float4 info, float3 d, float r) {
    float mip=r>=.8?3.0-5.0*r : r>=.4?5.0-7.5*r : r>=.21?2.0+(.4-r)/.095 : -2.0*log2(1.16*r);
    mip=clamp(mip,-2.0,info.z);
    float low=floor(mip);
    return mix(probeLevel(atlas,info,d,low),probeLevel(atlas,info,d,min(low+1,info.z)),fract(mip))*info.w;
}

fragment ShadedPixel sceneColor(SceneVaryings p [[stage_in]], bool clockwise [[front_facing]],
                                ShadedPixel previous, constant Lighting &light [[buffer(0)]],
                                constant CameraFrame &c [[buffer(1)]], device const float4 *atlas [[buffer(2)]]) {
    // The color tile's fourth channel stores per-sample camera depth. Raster-order
    // groups serialize overlapping fragments while preserving opaque depth testing.
    if(p.position.z>previous.value.a) discard_fragment();
    if((p.side<0.5 && clockwise) || (p.side>0.5 && p.side<1.5 && !clockwise)) discard_fragment();
    float3 color=p.albedo;
    if(p.roughness>=0) {
        float3 N=normalize(p.normal)*(clockwise?-1.0:1.0), V=normalize(c.eye.xyz-p.world);
        float3 geometryRoughness=max(abs(dfdx(N)),abs(dfdy(N)));
        float rough=clamp(max(p.roughness,0.0525)+max(geometryRoughness.x,max(geometryRoughness.y,geometryRoughness.z)),0.0525,1.0);
        float a2=rough*rough*rough*rough;
        float nv=saturate(dot(N,V));
        float3 diffuse=p.albedo*(1.0-p.metalness)/M_PI_F;
        float3 f0=mix(float3(0.04),p.albedo,p.metalness);
        color=p.emission+diffuse*mix(light.hemiGround.rgb,light.hemiSky.rgb,0.5+0.5*dot(N,light.hemiDir.xyz));
        if(light.probe.x>0){
            float4 dfg=rough*float4(-1,-.0275,-.572,.022)+float4(1,.0425,1.04,-.04);
            float lum=min(dfg.x*dfg.x,exp2(-9.28*nv))*dfg.x+dfg.y;
            float2 fab=float2(-1.04,1.04)*lum+dfg.zw;
            float3 single=f0*fab.x+fab.y, average=f0+(1-f0)/21.0;
            float lost=1-fab.x-fab.y;
            float3 multi=single*average*lost/(1-lost*average);
            float3 total=single+multi;
            float3 indirectDiffuse=p.albedo*(1-p.metalness)*(1-max(total.x,max(total.y,total.z)));
            float3 reflected=normalize(mix(reflect(-V,N),N,rough*rough));
            color+=environment(atlas,light.probe,reflected,rough)*single;
            color+=environment(atlas,light.probe,N,1.0)*(multi+indirectDiffuse);
        }
        for(uint i=0;i<4;i++){
            float3 L=light.lights[2*i].xyz, radiance=light.lights[2*i+1].rgb;
            float nl=saturate(dot(N,L));
            if(nl<=0.0) continue;
            float3 H=normalize(L+V);
            float nh=saturate(dot(N,H)), vh=saturate(dot(V,H));
            float denominator=nh*nh*(a2-1.0)+1.0;
            float D=a2/(M_PI_F*denominator*denominator);
            float visibility=0.5/max(1e-6,nl*sqrt(a2+(1-a2)*nv*nv)+nv*sqrt(a2+(1-a2)*nl*nl));
            float3 F=mix(f0,float3(1),exp2((-5.55473*vh-6.98316)*vh));
            color+=radiance*nl*(diffuse+F*D*visibility);
        }
    }
    float fogDepth=p.distance*light.fog.w;
    float fog=p.fog*(1.0-exp(-fogDepth*fogDepth));
    return {float4(mix(displaySRGB(color),light.fog.rgb,fog),p.position.z)};
}
