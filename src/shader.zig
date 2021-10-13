const std = @import("std");
const c = @cImport({
    @cInclude("epoxy/gl.h");
});
const math = @import("math.zig");
const Vec3 = math.Vec3;
const Mat4 = math.Mat4;

const c_allocator = std.heap.c_allocator;

fn compile_shader_from_source(filename: []const u8, name: []const u8, kind: c.GLenum) !c.GLuint {
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();
    var buffer: [5096]u8 = undefined;
    const bytes_read = try file.read(&buffer);
    const source = buffer[0..bytes_read];
    var vertex_shader = c.glCreateShader(kind);
    const source_ptr: ?[*]const u8 = source.ptr;
    const source_len = @intCast(c.GLint, source.len);
    c.glShaderSource(vertex_shader, 1, &source_ptr, &source_len);
    c.glCompileShader(vertex_shader);

    var ok: c.GLint = undefined;
    c.glGetShaderiv(vertex_shader, c.GL_COMPILE_STATUS, &ok);
    if (ok == 0) {
        var error_size: c.GLint = undefined;
        c.glGetShaderiv(vertex_shader, c.GL_INFO_LOG_LENGTH, &error_size);

        const log = try c_allocator.alloc(u8, @intCast(usize, error_size));
        c.glGetShaderInfoLog(vertex_shader, error_size, &error_size, log.ptr);
        std.debug.panic("Error compiling {s} shader: {s}", .{ name, log });
    }
    return vertex_shader;
}

fn glGetUniformLocation(program: c.GLuint, name: []const u8) !c_int {
    const loc = c.glGetUniformLocation(program, name.ptr);
    if (loc == -1) {
        std.debug.panic("Cannot get uniform location: {s}", .{name});
    }
    return loc;
}

pub const Shader = struct {
    program: c.GLuint,

    pub fn init(vertex: []const u8, fragment: []const u8) !Shader {
        const vertex_shader = try compile_shader_from_source(vertex, "vertex", c.GL_VERTEX_SHADER);
        defer c.glDeleteShader(vertex_shader);
        const fragment_shader = try compile_shader_from_source(fragment, "fragment", c.GL_FRAGMENT_SHADER);
        defer c.glDeleteShader(fragment_shader);

        const program = c.glCreateProgram();
        c.glAttachShader(program, vertex_shader);
        c.glAttachShader(program, fragment_shader);
        c.glLinkProgram(program);

        var ok: c.GLint = undefined;
        c.glGetProgramiv(program, c.GL_LINK_STATUS, &ok);
        if (ok == 0) {
            var error_size: c.GLint = undefined;
            c.glGetProgramiv(program, c.GL_INFO_LOG_LENGTH, &error_size);

            const log = try c_allocator.alloc(u8, @intCast(usize, error_size));
            c.glGetProgramInfoLog(program, error_size, &error_size, log.ptr);
            std.debug.panic("Error linking program: {s}", .{log});
        }

        return Shader{ .program = program };
    }

    pub fn use(self: Shader) void {
        c.glUseProgram(self.program);
    }

    pub fn unuse(self: Shader) void {
        c.glUseProgram(0);
    }

    pub fn set_vec3(self: Shader, name: []const u8, vec: Vec3) !void {
        const loc = try glGetUniformLocation(self.program, name);
        // TODO: use 3fv with pointer to data
        c.glUniform3f(loc, vec.x, vec.y, vec.z);
    }

    pub fn set_mat4(self: Shader, name: []const u8, mat: Mat4) !void {
        const loc = try glGetUniformLocation(self.program, name);
        c.glUniformMatrix4fv(loc, 1, c.GL_TRUE, &mat.data);
    }
};
