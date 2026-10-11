#include <flutter/runtime_effect.glsl>

uniform vec2 u_resolution;
uniform float u_time;
uniform float u_x;
uniform float u_y;
uniform float u_zoom;
uniform sampler2D u_tex0;

const float PI = 3.1415926;

float rand(vec2 co) {
    return fract(sin(mod(dot(co, vec2(12.9898, 78.233)), PI)) * 43758.5453);
}

out vec4 fragColor;

void main() {
    float R = min(u_resolution.x, u_resolution.y) / 3.0;
    if (u_zoom != 0.0) R *= u_zoom;

    // Android GLRenderer uses OpenGL's bottom-left origin. FlutterFragCoord()
    // is top-left based here, so mirror only Y before applying the exact
    // Android formula. This keeps the globe north-up while preserving
    // the same rotation equation and texture coordinates as Android.
    vec2 frag = FlutterFragCoord().xy;
    frag.y = u_resolution.y - frag.y;
    vec2 xy = u_resolution / 2.0 - frag;
    float r = length(xy);

    if (r < R) {
        vec3 xyz = mat3(
            1.0, 0.0, 0.0,
            0.0, cos(-u_y), -sin(-u_y),
            0.0, sin(-u_y),  cos(-u_y)
        ) * vec3(xy, sqrt(R * R - r * r));

        vec2 longLat = vec2(
            (-atan(xyz.x, xyz.z) - u_x) / PI / 2.0,
            asin(xyz.y / R) / PI + 0.5
        );

        // Android/OpenGL uses the texture's default repeat wrap on X.
        // RuntimeEffect samplers are normalized but do not inherit GL_REPEAT,
        // so make that repeat explicit to preserve the Android behavior.
        longLat.x = mod(longLat.x, 1.0);
        if (longLat.x < 0.0) longLat.x += 1.0;
        longLat.y = clamp(longLat.y, 0.0, 1.0);
        fragColor = texture(u_tex0, longLat);
    } else {
        float v = 4.4 - r / R * 3.7;
        float noiseValue = rand(vec2(
            floor(-u_x * 10.0 + xy.x / 4.0),
            floor(u_y * 10.0 + xy.y / 4.0)
        ));
        if (noiseValue > 0.997) {
            v = abs(sin(u_time + (1.0 - noiseValue) / 0.003 * 2.0 * PI));
        }
        fragColor = vec4(v, v, v, 1.0);
    }
}
