const std = @import("std");
const Io = std.Io;
const scan = @import("scan.zig");
const Parser = @import("parser.zig").Parser;
const ast = @import("ast.zig");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    var values = std.StringHashMap(ast.Value).init(arena);
    defer values.deinit();

    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 2) {
        std.debug.print("usage: gate 'expression'", .{});
        return;
    }

    var parser = Parser.init(arena, args[1]);
    const expr = try parser.parse();

    for (args[2..]) |fact| {
        if (std.mem.find(u8, fact, "=")) |kv_sep| {
            const key = fact[0..kv_sep];
            const value = parseFactValue(fact[kv_sep + 1 ..]);
            try values.put(key, value);
        }
    }

    const result = eval(expr, &values, parser.scanner.source) catch |err| {
        std.debug.print("evaluation error: {s}\n", .{@errorName(err)});
        std.process.exit(2);
    };

    switch (result) {
        .boolean => |passed| std.process.exit(if (passed) 0 else 1),
        else => {
            std.debug.print("expression did not evaluate to a boolean\n", .{});
            std.process.exit(2);
        },
    }
}

fn parseFactValue(raw: []const u8) ast.Value {
    if (std.mem.eql(u8, raw, "true")) {
        return .{ .boolean = true };
    }
    if (std.mem.eql(u8, raw, "false")) {
        return .{ .boolean = false };
    }

    if (std.fmt.parseInt(i64, raw, 10)) |integer| {
        return .{ .integer = integer };
    } else |_| {
        return .{ .string = raw };
    }
}

const EvalError = error{
    NotImplemented,
    TypeMismatch,
    UnsupportedOperator,
    UnknownIdentifier,
};

fn eval(
    expression: *const ast.Expr,
    facts: *const std.StringHashMap(ast.Value),
    source: []const u8,
) EvalError!ast.Value {
    switch (expression.*) {
        .binary => |binary| {
            const left = try eval(binary.left, facts, source);
            const right = try eval(binary.right, facts, source);

            return switch (binary.operator.token_type) {
                .LESS => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int < right_int },
                        else => error.TypeMismatch,
                    },
                    else => error.TypeMismatch,
                },
                .LESS_EQUAL => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int <= right_int },
                        else => error.TypeMismatch,
                    },
                    else => error.TypeMismatch,
                },
                .GREATER => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int > right_int },
                        else => error.TypeMismatch,
                    },
                    else => error.TypeMismatch,
                },
                .GREATER_EQUAL => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int >= right_int },
                        else => error.TypeMismatch,
                    },
                    else => error.TypeMismatch,
                },
                .EQUAL_EQUAL => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int == right_int },
                        else => error.TypeMismatch,
                    },
                    .boolean => |left_bool| switch (right) {
                        .boolean => |right_bool| ast.Value{ .boolean = left_bool == right_bool },
                        else => error.TypeMismatch,
                    },
                    .string => |left_string| switch (right) {
                        .string => |right_string| ast.Value{ .boolean = std.mem.eql(u8, left_string, right_string) },
                        else => error.TypeMismatch,
                    },
                },
                .BANG_EQUAL => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int != right_int },
                        else => error.TypeMismatch,
                    },
                    .boolean => |left_bool| switch (right) {
                        .boolean => |right_bool| ast.Value{ .boolean = left_bool != right_bool },
                        else => error.TypeMismatch,
                    },
                    .string => |left_string| switch (right) {
                        .string => |right_string| ast.Value{ .boolean = !std.mem.eql(u8, left_string, right_string) },
                        else => error.TypeMismatch,
                    },
                },
                else => error.NotImplemented,
            };
        },
        .literal => |literal| return literal.value,
        .identifier => |identifier| {
            const token = identifier.token;
            const name = source[token.start_pos..token.end_pos];
            return facts.get(name) orelse error.UnknownIdentifier;
        },
        .unary => |unary| {
            const operand = try eval(unary.operand, facts, source);

            return switch (operand) {
                .boolean => |value| ast.Value{ .boolean = !value },
                else => error.TypeMismatch,
            };
        },
        .logical => |logical| {
            const left = try eval(logical.left, facts, source);
            const left_bool = switch (left) {
                .boolean => |value| value,
                else => return error.TypeMismatch,
            };

            switch (logical.operator.token_type) {
                .AND_AND => {
                    if (!left_bool) return ast.Value{ .boolean = false };
                },
                .OR_OR => {
                    if (left_bool) return ast.Value{ .boolean = true };
                },
                else => return error.UnsupportedOperator,
            }

            const right = try eval(logical.right, facts, source);
            return switch (right) {
                .boolean => |value| ast.Value{ .boolean = value },
                else => error.TypeMismatch,
            };
        },
    }
}

test {
    _ = @import("scan.zig");
    _ = @import("parser.zig");
    std.testing.refAllDecls(@This());
}
