#include <metal_stdlib>
using namespace metal;

// x,y,z rotations compose in Three.js Euler order XYZ. GPU positions use Metal clip depth.
vertex float4 boxVertex(uint id [[vertex_id]], constant float4 *u [[buffer(0)]]) {
    constexpr float3 corners[] = {
        {-0.5,-0.5,-0.5}, {0.5,-0.5,-0.5}, {0.5,0.5,-0.5}, {-0.5,0.5,-0.5},
        {-0.5,-0.5,0.5},  {0.5,-0.5,0.5},  {0.5,0.5,0.5},  {-0.5,0.5,0.5}
    };
    constexpr ushort indices[] = {
        0,2,1,0,3,2, 4,5,6,4,6,7, 0,4,7,0,7,3,
        1,2,6,1,6,5, 3,7,6,3,6,2, 0,1,5,0,5,4
    };
    float3 p = corners[indices[id]] * u[0].xyz;
    float3 s = sin(u[1].xyz), c = cos(u[1].xyz);
    p.xy = float2(c.z*p.x-s.z*p.y, s.z*p.x+c.z*p.y);
    p.xz = float2(c.y*p.x+s.y*p.z, -s.y*p.x+c.y*p.z);
    p.yz = float2(c.x*p.y-s.x*p.z, s.x*p.y+c.x*p.z);
    p += u[2].xyz;
    p=float3(dot(p,u[4].xyz),dot(p,u[5].xyz),dot(p,u[6].xyz));
    float4 proj = u[3];
    return float4(p.x*proj.x,p.y*proj.y,p.z*proj.z+proj.w,-p.z);
}

fragment float4 boxColor(constant float4 &color [[buffer(0)]], bool front [[front_facing]]) {
    // The binding uses Metal's default clockwise winding. Three.js uses CCW.
    if (front) discard_fragment();
    return color;
}

vertex float4 screenVertex(uint id [[vertex_id]]) {
    constexpr float2 triangle[] = {{-1,-1},{3,-1},{-1,3}};
    return float4(triangle[id],0,1);
}

fragment float4 resolveColor(float4 pos [[position]], texture2d<float, access::read> source [[texture(0)]],
                             constant uint &scale [[buffer(0)]]) {
    uint2 xy = uint2(pos.xy)*scale;
    if (scale == 1) return float4(source.read(xy).rgb,1.0);
    return float4((source.read(xy)+source.read(xy+uint2(1,0))+source.read(xy+uint2(0,1))+source.read(xy+1)).rgb*0.25,1.0);
}
