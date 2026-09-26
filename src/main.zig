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

    var eval_diagnostic: ?EvalDiagnostic = null;
    const result = eval(expr, &values, parser.scanner.source, &eval_diagnostic) catch |err| {
        if (eval_diagnostic) |diagnostic| {
            std.debug.print("evaluation error at byte {d}: {s}\n", .{ diagnostic.offset, diagnostic.message });
        } else {
            std.debug.print("evaluation error: {s}\n", .{@errorName(err)});
        }
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

const EvalDiagnostic = struct {
    message: []const u8,
    offset: usize,
};

fn fail(
    diagnostic: *?EvalDiagnostic,
    message: []const u8,
    offset: usize,
    err: EvalError,
) EvalError {
    diagnostic.* = .{ .message = message, .offset = offset };
    return err;
}

fn eval(
    expression: *const ast.Expr,
    facts: *const std.StringHashMap(ast.Value),
    source: []const u8,
    diagnostic: *?EvalDiagnostic,
) EvalError!ast.Value {
    switch (expression.*) {
        .binary => |binary| {
            const left = try eval(binary.left, facts, source, diagnostic);
            const right = try eval(binary.right, facts, source, diagnostic);

            const offset = binary.operator.start_pos;
            return switch (binary.operator.token_type) {
                .LESS => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int < right_int },
                        else => fail(diagnostic, "comparison requires two integers", offset, error.TypeMismatch),
                    },
                    else => fail(diagnostic, "comparison requires two integers", offset, error.TypeMismatch),
                },
                .LESS_EQUAL => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int <= right_int },
                        else => fail(diagnostic, "comparison requires two integers", offset, error.TypeMismatch),
                    },
                    else => fail(diagnostic, "comparison requires two integers", offset, error.TypeMismatch),
                },
                .GREATER => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int > right_int },
                        else => fail(diagnostic, "comparison requires two integers", offset, error.TypeMismatch),
                    },
                    else => fail(diagnostic, "comparison requires two integers", offset, error.TypeMismatch),
                },
                .GREATER_EQUAL => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int >= right_int },
                        else => fail(diagnostic, "comparison requires two integers", offset, error.TypeMismatch),
                    },
                    else => fail(diagnostic, "comparison requires two integers", offset, error.TypeMismatch),
                },
                .EQUAL_EQUAL => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int == right_int },
                        else => fail(diagnostic, "cannot compare values of different types", offset, error.TypeMismatch),
                    },
                    .boolean => |left_bool| switch (right) {
                        .boolean => |right_bool| ast.Value{ .boolean = left_bool == right_bool },
                        else => fail(diagnostic, "cannot compare values of different types", offset, error.TypeMismatch),
                    },
                    .string => |left_string| switch (right) {
                        .string => |right_string| ast.Value{ .boolean = std.mem.eql(u8, left_string, right_string) },
                        else => fail(diagnostic, "cannot compare values of different types", offset, error.TypeMismatch),
                    },
                },
                .BANG_EQUAL => switch (left) {
                    .integer => |left_int| switch (right) {
                        .integer => |right_int| ast.Value{ .boolean = left_int != right_int },
                        else => fail(diagnostic, "cannot compare values of different types", offset, error.TypeMismatch),
                    },
                    .boolean => |left_bool| switch (right) {
                        .boolean => |right_bool| ast.Value{ .boolean = left_bool != right_bool },
                        else => fail(diagnostic, "cannot compare values of different types", offset, error.TypeMismatch),
                    },
                    .string => |left_string| switch (right) {
                        .string => |right_string| ast.Value{ .boolean = !std.mem.eql(u8, left_string, right_string) },
                        else => fail(diagnostic, "cannot compare values of different types", offset, error.TypeMismatch),
                    },
                },
                else => fail(diagnostic, "unsupported binary operator", offset, error.NotImplemented),
            };
        },
        .literal => |literal| return literal.value,
        .identifier => |identifier| {
            const token = identifier.token;
            const name = source[token.start_pos..token.end_pos];
            if (facts.get(name)) |value| return value;
            return fail(diagnostic, "unknown identifier", token.start_pos, error.UnknownIdentifier);
        },
        .unary => |unary| {
            const operand = try eval(unary.operand, facts, source, diagnostic);

            return switch (operand) {
                .boolean => |value| ast.Value{ .boolean = !value },
                else => fail(diagnostic, "'!' requires a boolean operand", unary.operator.start_pos, error.TypeMismatch),
            };
        },
        .logical => |logical| {
            const left = try eval(logical.left, facts, source, diagnostic);
            const left_bool = switch (left) {
                .boolean => |value| value,
                else => return fail(diagnostic, "logical operator requires boolean operands", logical.operator.start_pos, error.TypeMismatch),
            };

            switch (logical.operator.token_type) {
                .AND_AND => {
                    if (!left_bool) return ast.Value{ .boolean = false };
                },
                .OR_OR => {
                    if (left_bool) return ast.Value{ .boolean = true };
                },
                else => return fail(diagnostic, "unsupported logical operator", logical.operator.start_pos, error.UnsupportedOperator),
            }

            const right = try eval(logical.right, facts, source, diagnostic);
            return switch (right) {
                .boolean => |value| ast.Value{ .boolean = value },
                else => fail(diagnostic, "logical operator requires boolean operands", logical.operator.start_pos, error.TypeMismatch),
            };
        },
    }
}

test "evaluation errors include the operator byte offset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var parser = Parser.init(arena.allocator(), "4 >= \"three\"");
    const expr = try parser.parse();
    const facts = std.StringHashMap(ast.Value).init(arena.allocator());
    var diagnostic: ?EvalDiagnostic = null;

    try std.testing.expectError(
        error.TypeMismatch,
        eval(expr, &facts, parser.scanner.source, &diagnostic),
    );
    try std.testing.expectEqual(@as(usize, 2), diagnostic.?.offset);
    try std.testing.expectEqualStrings("comparison requires two integers", diagnostic.?.message);
}

test {
    _ = @import("scan.zig");
    _ = @import("parser.zig");
    std.testing.refAllDecls(@This());
}
