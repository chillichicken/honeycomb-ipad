#include <metal_stdlib>
using namespace metal;

// Must match TileInstance / GPUUniforms in TileRenderer.swift, field for field.
struct TileInstance {
    float2 pos;   // tile center, world units relative to the camera center
    uint color;   // 0xRRGGBB
    uint flags;   // bits 0-7: orientation, bit 8: outlined (selected)
};

struct Uniforms {
    float4 view;      // width, height (points), zoom, tileSize (world units)
    float4 grid;      // spacing, phaseX, phaseY (camera center mod spacing), neighborDist
    float4 misc;      // cornerCount, drawable scale, fabricPhaseX, fabricPhaseY
    float4 bgCenter;
    float4 bgEdge;
    float4 gridColor; // rgb + alpha
    float4 accent;
    float4 corners[6]; // 2 orientations x 3 float4, two corners each: unit vectors
};

float3 unpackColor(uint c) {
    return float3(float((c >> 16) & 0xFFu), float((c >> 8) & 0xFFu), float(c & 0xFFu)) / 255.0;
}

float2 cornerAt(constant Uniforms& u, int orientation, int k) {
    float4 v = u.corners[orientation * 3 + k / 2];
    return (k & 1) ? v.zw : v.xy;
}

// MARK: Background: radial gradient plus the faint world-anchored dot grid

struct BackdropOut {
    float4 position [[position]];
};

vertex BackdropOut backdropVertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2u), float(vid & 2u));  // one big triangle
    BackdropOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

fragment float4 backdropFragment(BackdropOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pt = in.position.xy / u.misc.y;  // points, origin top left
    float2 mid = u.view.xy * 0.5;
    float t = clamp(length(pt - mid) / length(mid), 0.0, 1.0);
    float3 col = mix(u.bgCenter.rgb, u.bgEdge.rgb, t);

    float zoom = u.view.z;
    float spacing = u.grid.x;
    float2 w = (pt - mid) / zoom + u.grid.yz;         // world units, aligned to the lattice
    float2 nearest = round(w / spacing) * spacing;
    float d = length(w - nearest) * zoom;               // distance to the nearest dot, in points
    float dotAlpha = 1.0 - smoothstep(1.0, 2.0, d);
    col = mix(col, u.gridColor.rgb, dotAlpha * u.gridColor.a);
    return float4(col, 1.0);
}

// MARK: Tiles: one instanced quad each; the shape is a polygon distance field

struct TileOut {
    float4 position [[position]];
    float2 local;     // world units from the tile center
    float2 worldRel;  // world units from the camera center
    uint color [[flat]];
    uint flags [[flat]];
};

vertex TileOut tileVertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                          constant TileInstance* tiles [[buffer(0)]],
                          constant Uniforms& u [[buffer(1)]]) {
    TileInstance t = tiles[iid];
    float2 q = float2((vid & 1u) ? 1.0 : -1.0, (vid & 2u) ? 1.0 : -1.0);
    float zoom = u.view.z;
    float R = u.view.w;
    bool merged = R * zoom < 3.0;
    // far out a tile is a few pixels: a flat square, padded so neighbors overlap
    float halfSize = merged ? max(u.grid.w * zoom, 1.0) * 1.05 / zoom : R * 1.18;

    float2 local = q * halfSize;
    float2 world = t.pos + local;
    float2 screen = world * zoom + u.view.xy * 0.5;
    TileOut o;
    o.position = float4(screen.x / u.view.x * 2.0 - 1.0, 1.0 - screen.y / u.view.y * 2.0, 0.0, 1.0);
    o.local = local;
    o.worldRel = world;
    o.color = t.color;
    o.flags = t.flags;
    return o;
}

// distance (world units) from the polygon scaled to radius s; negative inside
float polyD(thread const float* t, thread const float* apothem, int n, float s, thread int& edge) {
    float d = -1e9;
    edge = 0;
    for (int k = 0; k < n; k++) {
        float v = t[k] - s * apothem[k];
        if (v > d) { d = v; edge = k; }
    }
    return d;
}

float ring(float d, float halfWidth, float px) {
    return 1.0 - smoothstep(halfWidth - px, halfWidth + px, abs(d));
}

float3 overlayBlend(float3 base, float v) {
    return mix(2.0 * base * v, 1.0 - 2.0 * (1.0 - base) * (1.0 - v), step(0.5, base));
}

fragment float4 tileFragment(TileOut in [[stage_in]], constant Uniforms& u [[buffer(1)]]) {
    float zoom = u.view.z;
    float R = u.view.w;
    float3 base = unpackColor(in.color);
    float radiusPx = R * zoom;
    if (radiusPx < 3.0) return float4(base, 1.0);

    int orientation = int(in.flags & 0xFFu);
    bool outlined = (in.flags & 0x100u) != 0u;
    bool medium = radiusPx >= 12.0;   // adds the inner honeycomb wall
    bool full = radiusPx >= 30.0;     // adds the fabric grain and the stitched seam
    int n = int(u.misc.x);
    float px = 1.0 / (zoom * u.misc.y);  // one drawable pixel, in world units
    float2 p = in.local;

    // per-edge plane: t = distance of p along the outward normal, apothem of the unit polygon
    float t[6];
    float apothem[6];
    float2 tangent[6];
    for (int k = 0; k < n; k++) {
        float2 c0 = cornerAt(u, orientation, k);
        float2 c1 = cornerAt(u, orientation, (k + 1) % n);
        float2 e = c1 - c0;
        float2 nr = normalize(float2(e.y, -e.x));
        if (dot(nr, c0) < 0.0) nr = -nr;
        t[k] = dot(p, nr);
        apothem[k] = dot(c0, nr);
        tangent[k] = float2(-nr.y, nr.x);
    }

    int edge;
    float fillCov = 1.0 - smoothstep(-px, px, polyD(t, apothem, n, R, edge));
    float3 col = base;

    if (full) {
        // woven-cloth grain: a twill crosshatch plus noise, anchored to the world and
        // overlay-blended so it darkens and lightens the color like real threads
        float2 tex = floor(in.worldRel + u.misc.zw);
        float2 m = tex - 14.0 * floor(tex / 14.0);
        float weave = fmod(m.x + m.y, 4.0) < 2.0 ? 34.0 : -34.0;
        float grain = (fract(sin(dot(m, float2(12.9898, 78.233))) * 43758.5453) - 0.5) * 34.0;
        float v = clamp((128.0 + weave + grain) / 255.0, 0.0, 1.0);
        col = mix(col, overlayBlend(base, v), 0.85);
    }

    // darker border
    float d = polyD(t, apothem, n, R - 1.5, edge);
    col = mix(col, clamp(base - 60.0 / 255.0, 0.0, 1.0), ring(d, 1.5, px));

    if (full) {
        // stitched seam: a dashed line just inside the border
        d = polyD(t, apothem, n, R - 6.0, edge);
        float along = dot(p, tangent[edge]) / 5.5 + 0.37 * float(edge);
        float dash = step(fract(along), 2.5 / 5.5);
        col = mix(col, float3(1.0, 0.98, 0.92), ring(d, 0.6, px) * dash * 0.5);
    }

    if (medium) {
        // inner cell wall for the honeycomb look
        d = polyD(t, apothem, n, R * 0.72, edge);
        col = mix(col, clamp(base + 35.0 / 255.0, 0.0, 1.0), ring(d, 1.0, px));
    }

    float alpha = fillCov;
    if (outlined) {
        d = polyD(t, apothem, n, R + 4.0, edge);
        float o = ring(d, max(1.25, 0.75 / zoom), px) * 0.95;
        float outAlpha = o + alpha * (1.0 - o);
        col = (u.accent.rgb * o + col * alpha * (1.0 - o)) / max(outAlpha, 1e-4);
        alpha = outAlpha;
    }
    if (alpha < 0.002) discard_fragment();
    return float4(col, alpha);
}
