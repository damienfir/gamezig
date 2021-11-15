const std = @import("std");
const c = @cImport({
    @cInclude("epoxy/gl.h");
    @cInclude("GLFW/glfw3.h");
});
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;
const Axes = @import("axes.zig").Axes;
const Camera = @import("camera.zig").Camera;
const Shader = @import("shader.zig").Shader;

fn render_buffers() void {
    const view = camera.get_view();
    pieces.items[0].gl_buffer.shader.use();
    defer pieces.items[0].gl_buffer.shader.unuse();
    for (pieces.items) |piece| {
        const buf = piece.gl_buffer;
        // TODO: move shader out of structure, render all with same shader after grouping
        // buf.shader.use();
        // defer buf.shader.unuse();

        c.glBindVertexArray(buf.vao);
        defer c.glBindVertexArray(0);

        const transform = Mat4.rotation_y(piece.rotation).mul(Mat4.translation(piece.position));

        try buf.shader.set_vec3("color", piece.color);
        try buf.shader.set_mat4("model", transform);
        try buf.shader.set_mat4("projection", camera.projection);
        try buf.shader.set_mat4("view", view);
        c.glDrawArrays(c.GL_TRIANGLES, 0, @intCast(c_int, buf.n_vertices));
    }
}

const RPM = struct {
    value: f32,

    pub fn set(v: f32) RPM {
        return RPM{ .value = v };
    }
};

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

const GLBuffer = struct {
    vao: c.GLuint,
    shader: Shader,
    n_vertices: u32,
};

const Mesh = struct {
    vertices: []Vec3,
    normals: []Vec3,
};

const Piece = struct {
    mesh: Mesh,
    gl_buffer: GLBuffer,
    rotation: f32,
    rotation_speed: RPM,
    position: Vec3,
    color: Vec3,
};

const Controls = struct {
    move_forwards: bool,
    move_backwards: bool,
    move_left: bool,
    move_right: bool,
    dx: f32,
    dy: f32,
};

var controls: Controls = undefined;
var camera = Camera.init(window_ratio);
var axes: Axes = undefined;
var pieces = std.ArrayList(Piece).init(&gpa.allocator);

fn normal_for_face(vertices: [*]Vec3) Vec3 {
    const v = vertices[1].sub(vertices[0]);
    const w = vertices[2].sub(vertices[0]);
    return v.cross(w).normalize();
}

fn compute_normals(vertices: []Vec3) ![]Vec3 {
    var normals = try gpa.allocator.alloc(Vec3, vertices.len);
    var i: u32 = 0;
    while (i < vertices.len) : (i += 3) {
        const n = normal_for_face(vertices.ptr + i);
        normals[i] = n;
        normals[i + 1] = n;
        normals[i + 2] = n;
    }
    return normals;
}

fn polygon_piece(radius: f32, thickness: f32, n_sides: u32) !Mesh {
    var i: u32 = 0;
    var mesh: Mesh = undefined;
    const stride = 3 * 4;
    mesh.vertices = try gpa.allocator.alloc(Vec3, n_sides * stride);
    while (i < n_sides) : (i += 1) {
        const angle_a = @intToFloat(f32, i) * 2.0 * std.math.pi / @intToFloat(f32, n_sides);
        const angle_b = @intToFloat(f32, i + 1) * 2.0 * std.math.pi / @intToFloat(f32, n_sides);

        const bottom_a = Vec3.init(radius * @cos(angle_a), 0, radius * @sin(angle_a));
        const bottom_b = Vec3.init(radius * @cos(angle_b), 0, radius * @sin(angle_b));
        const bottom_c = Vec3.init(0, 0, 0);

        const top_a = bottom_a.add(Vec3.init(0, thickness, 0));
        const top_b = bottom_b.add(Vec3.init(0, thickness, 0));
        const top_c = bottom_c.add(Vec3.init(0, thickness, 0));

        mesh.vertices[i * stride + 0] = bottom_a;
        mesh.vertices[i * stride + 1] = bottom_b;
        mesh.vertices[i * stride + 2] = bottom_c;

        mesh.vertices[i * stride + 3] = top_a;
        mesh.vertices[i * stride + 4] = top_c;
        mesh.vertices[i * stride + 5] = top_b;

        mesh.vertices[i * stride + 6] = bottom_a;
        mesh.vertices[i * stride + 7] = top_b;
        mesh.vertices[i * stride + 8] = top_a;

        mesh.vertices[i * stride + 9] = bottom_a;
        mesh.vertices[i * stride + 10] = bottom_b;
        mesh.vertices[i * stride + 11] = top_b;
    }
    mesh.normals = try compute_normals(mesh.vertices);
    return mesh;
}

fn gl_buffer_from_mesh(mesh: Mesh) !GLBuffer {
    var buf: GLBuffer = undefined;
    buf.n_vertices = @intCast(u32, mesh.vertices.len);
    buf.shader = try Shader.init("shaders/phong_vertex.glsl", "shaders/phong_fragment.glsl");

    var data = try gpa.allocator.alloc(Vec3, 2 * mesh.vertices.len);
    defer gpa.allocator.free(data);
    var i: u32 = 0;
    while (i < mesh.vertices.len) : (i += 1) {
        data[i * 2] = mesh.vertices[i];
        data[i * 2 + 1] = mesh.normals[i];
    }

    c.glGenVertexArrays(1, &buf.vao);
    var vbo: c.GLuint = undefined;
    c.glGenBuffers(1, &vbo);
    c.glBindVertexArray(buf.vao);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);
    c.glBufferData(c.GL_ARRAY_BUFFER, @intCast(c_long, data.len * @sizeOf(Vec3)), data.ptr, c.GL_STATIC_DRAW);
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 2 * @sizeOf(Vec3), null);
    c.glEnableVertexAttribArray(0);
    c.glVertexAttribPointer(1, 3, c.GL_FLOAT, c.GL_FALSE, 2 * @sizeOf(Vec3), @intToPtr(*c_void, @sizeOf(Vec3)));
    c.glEnableVertexAttribArray(1);

    return buf;
}

fn draw() void {
    c.glClearColor(0, 0, 0, 0);
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    // axes.draw(camera);
    render_buffers();
}

fn update_camera(dt: f32) void {
    var velocity = Vec3.init(0, 0, 0);
    if (controls.move_forwards) {
        velocity = velocity.add(camera.direction);
    } else if (controls.move_backwards) {
        velocity = velocity.sub(camera.direction);
    }

    if (controls.move_right) {
        velocity = velocity.add(camera.get_horizontal_vector());
    } else if (controls.move_left) {
        velocity = velocity.sub(camera.get_horizontal_vector());
    }

    velocity = velocity.scale(camera.speed);

    camera.position = camera.position.add(velocity.scale(dt));

    camera.rotate_direction(controls.dx, controls.dy);
    controls.dx = 0;
    controls.dy = 0;
}

fn keyboard_camera(key: c_int, action: c_int) void {
    if (key == c.GLFW_KEY_W) {
        if (action == c.GLFW_PRESS) {
            controls.move_backwards = false;
            controls.move_forwards = true;
        } else if (action == c.GLFW_RELEASE) {
            controls.move_forwards = false;
        }
    }

    if (key == c.GLFW_KEY_S) {
        if (action == c.GLFW_PRESS) {
            controls.move_forwards = false;
            controls.move_backwards = true;
        } else if (action == c.GLFW_RELEASE) {
            controls.move_backwards = false;
        }
    }

    if (key == c.GLFW_KEY_A) {
        if (action == c.GLFW_PRESS) {
            controls.move_right = false;
            controls.move_left = true;
        } else if (action == c.GLFW_RELEASE) {
            controls.move_left = false;
        }
    }

    if (key == c.GLFW_KEY_D) {
        if (action == c.GLFW_PRESS) {
            controls.move_left = false;
            controls.move_right = true;
        } else if (action == c.GLFW_RELEASE) {
            controls.move_right = false;
        }
    }
}

const Delta = struct {
    prev_x: f32,
    prev_y: f32,
    already_moved: bool,

    fn init() Delta {
        return Delta{ .prev_x = 0, .prev_y = 0, .already_moved = false };
    }

    fn get_delta(self: *Delta, x: f32, y: f32) Pair(f32) {
        if (!self.already_moved) {
            self.already_moved = true;
            self.prev_x = x;
            self.prev_y = y;
        }
        const dx = x - self.prev_x;
        const dy = y - self.prev_y;
        self.prev_x = x;
        self.prev_y = y;
        return Pair(f32){ .a = dx, .b = dy };
    }
};

var mouse_delta = Delta.init();

fn mouse_camera(xpos: f64, ypos: f64) void {
    const delta = mouse_delta.get_delta(@floatCast(f32, xpos), @floatCast(f32, ypos));
    controls.dx = delta.a;
    controls.dy = -delta.b;
}

fn update(dt: f32) void {
    for (pieces.items) |*piece| {
        piece.*.rotation += piece.rotation_speed.value * dt;
    }

    update_camera(dt);
}

fn glfw_key_callback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) callconv(.C) void {
    if (key == c.GLFW_KEY_ESCAPE and action == c.GLFW_PRESS) {
        c.glfwSetWindowShouldClose(window, 1);
    }

    keyboard_camera(key, action);
}

fn Pair(comptime T: type) type {
    return struct { a: T, b: T };
}

var mouse_throttle: std.time.Timer = undefined;
fn glfw_cursor_callback(window: ?*c.GLFWwindow, xpos: f64, ypos: f64) callconv(.C) void {
    if (mouse_throttle.read() < @floatToInt(u64, (1.0 / 60.0) * 1e9)) {
        return;
    }
    mouse_throttle.reset();

    mouse_camera(xpos, ypos);
}

const window_width = 1920;
var window_height: u32 = undefined;
const window_ratio = 16.0 / 9.0;

fn print(x: anytype) void {
    std.debug.print("{}\n", .{x});
}

fn init() !void {
    axes = try Axes.init();

    const mesh = try polygon_piece(1, 0.1, 15);
    const piece = Piece{
        .mesh = mesh,
        .gl_buffer = try gl_buffer_from_mesh(mesh),
        .rotation = 0,
        .rotation_speed = RPM.set(0.4),
        .position = Vec3.init(0, 0, 0),
        .color = Vec3.init(1.0, 1.0, 1.0),
    };
    try pieces.append(piece);

    const mesh1 = try polygon_piece(0.5, 0.05, 9);
    const piece1 = Piece{
        .mesh = mesh1,
        .gl_buffer = try gl_buffer_from_mesh(mesh1),
        .rotation = 0,
        .rotation_speed = RPM.set(-0.4),
        .position = Vec3.init(0, 0.1, 0),
        .color = Vec3.init(0.7, 0.3, 0.1),
    };
    try pieces.append(piece1);

    c.glEnable(c.GL_DEPTH_TEST);
    // c.glEnable(c.GL_BLEND);
    // c.glBlendFunc(c.GL_SRC_ALPHA, c.GL_ONE_MINUS_SRC_ALPHA);
}

pub fn main() !void {
    _ = c.glfwInit();

    window_height = window_width / window_ratio;
    c.glfwWindowHint(c.GLFW_SAMPLES, 4);
    var window = c.glfwCreateWindow(window_width, @intCast(c_int, window_height), "Game", null, null);
    c.glfwMakeContextCurrent(window);
    c.glfwSetWindowPos(window, 100, 100);

    _ = c.glfwSetKeyCallback(window, glfw_key_callback);

    if (c.glfwRawMouseMotionSupported() != 0)
        c.glfwSetInputMode(window, c.GLFW_RAW_MOUSE_MOTION, c.GLFW_TRUE);
    _ = c.glfwSetInputMode(window, c.GLFW_CURSOR, c.GLFW_CURSOR_DISABLED);
    mouse_throttle = try std.time.Timer.start();
    _ = c.glfwSetCursorPosCallback(window, glfw_cursor_callback);

    try init();

    var timer = try std.time.Timer.start();

    while (c.glfwWindowShouldClose(window) == 0) {
        const dt = @intToFloat(f32, timer.lap()) / 1e9;
        update(dt);
        draw();

        c.glfwSwapBuffers(window);
        c.glfwPollEvents();
    }

    _ = c.glfwTerminate();
}
