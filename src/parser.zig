const std = @import("std");
const Token = @import("scan.zig").Token;
const Scanner = @import("scan.zig").Scanner;
const ast = @import("ast.zig");

pub const ParseErrorInfo = struct {
    message: []const u8,
    offset: usize,
};

const ParseFailed = error{ ParseFailed, OutOfMemory };

pub const Parser = struct {
    al: std.mem.Allocator,
    current: Token,
    previous: ?Token = null,
    scanner: Scanner,
    parse_error: ?ParseErrorInfo = null,

    pub fn init(al: std.mem.Allocator, source: []const u8) Parser {
        var scanner = Scanner.init(source);
        const current = scanner.scanToken();
        return .{
            .al = al,
            .scanner = scanner,
            .current = current,
        };
    }

    pub fn parse(self: *Parser) ParseFailed!*ast.Expr {
        const expr = try self.expression();

        if (self.current.token_type != .EOF) {
            self.parse_error = .{
                .message = "unexpected token after expression",
                .offset = self.current.start_pos,
            };
            return error.ParseFailed;
        }

        return expr;
    }

    fn makeExpr(self: *Parser, expr: ast.Expr) ParseFailed!*ast.Expr {
        const node = try self.al.create(ast.Expr);
        node.* = expr;
        return node;
    }

    fn expression(self: *Parser) ParseFailed!*ast.Expr {
        return self._or();
    }

    fn advance(self: *Parser) void {
        self.previous = self.current;
        self.current = self.scanner.scanToken();
    }

    fn unary(self: *Parser) ParseFailed!*ast.Expr {
        if (self.current.token_type == .BANG) {
            const operator = self.current;
            self.advance();
            const operand = try self.unary();
            return self.makeExpr(.{ .unary = .{ .operand = operand, .operator = operator } });
        }
        return try self.primary();
    }

    fn compare(self: *Parser) ParseFailed!*ast.Expr {
        const left = try self.unary();
        switch (self.current.token_type) {
            .EQUAL_EQUAL, .BANG_EQUAL, .LESS, .LESS_EQUAL, .GREATER, .GREATER_EQUAL => {
                const operator = self.current;
                self.advance();
                const right = try self.unary();
                return try self.makeExpr(.{ .binary = .{ .left = left, .operator = operator, .right = right } });
            },
            else => {},
        }
        return left;
    }

    fn _and(self: *Parser) ParseFailed!*ast.Expr {
        var left = try self.compare();
        while (self.current.token_type == .AND_AND) {
            const operator = self.current;
            self.advance();
            const right = try self.compare();
            left = try self.makeExpr(.{ .logical = .{ .left = left, .operator = operator, .right = right } });
        }
        return left;
    }

    fn _or(self: *Parser) ParseFailed!*ast.Expr {
        var left = try self._and();
        while (self.current.token_type == .OR_OR) {
            const operator = self.current;
            self.advance();
            const right = try self._and();
            left = try self.makeExpr(.{ .logical = .{ .left = left, .operator = operator, .right = right } });
        }
        return left;
    }

    pub fn primary(self: *Parser) ParseFailed!*ast.Expr {
        switch (self.current.token_type) {
            .NUMBER => {
                const current = self.current;
                self.advance();
                const num = std.fmt.parseInt(i64, self.scanner.fromToken(current), 10) catch {
                    self.parse_error = .{
                        .message = "failed to parse int",
                        .offset = self.current.start_pos,
                    };
                    return error.ParseFailed;
                };
                return self.makeExpr(.{ .literal = .{ .token = current, .value = .{ .integer = num } } });
            },
            .STRING => {
                const current = self.current;
                self.advance();
                var str = self.scanner.fromToken(current);
                str = std.mem.trimStart(u8, str, "\'\"");
                str = std.mem.trimEnd(u8, str, "\'\"");
                return self.makeExpr(.{ .literal = .{ .token = current, .value = .{ .string = str } } });
            },
            .IDENTIFIER => {
                const current = self.current;
                self.advance();
                const str = self.scanner.fromToken(current);
                if (std.mem.eql(u8, str, "true")) {
                    return self.makeExpr(.{ .literal = .{ .token = current, .value = .{ .boolean = true } } });
                } else if (std.mem.eql(u8, str, "false")) {
                    return self.makeExpr(.{ .literal = .{ .token = current, .value = .{ .boolean = false } } });
                } else {
                    return self.makeExpr(.{ .identifier = .{ .token = current } });
                }
            },
            .LEFT_PAREN => {
                self.advance();
                const expr = try self.expression();
                if (self.current.token_type != .RIGHT_PAREN) {
                    self.parse_error = .{
                        .message = "syntax error",
                        .offset = self.current.start_pos,
                    };
                    return error.ParseFailed;
                }
                self.advance();
                return expr;
            },
            else => {
                self.parse_error = .{
                    .message = "expected expression",
                    .offset = self.current.start_pos,
                };
                return error.ParseFailed;
            },
        }
    }
};

test "parses integer literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    var parser = Parser.init(al, "42");
    const expr = try parser.parse();

    switch (expr.*) {
        .literal => |literal| {
            try std.testing.expectEqual(@as(i64, 42), literal.value.integer);
            try std.testing.expectEqual(@as(usize, 0), literal.token.start_pos);
            try std.testing.expectEqual(@as(usize, 2), literal.token.end_pos);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "parses true and false boolean literals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const al = arena.allocator();
    var true_parser = Parser.init(al, "true");
    const true_expr = try true_parser.parse();
    switch (true_expr.*) {
        .literal => |literal| try std.testing.expect(literal.value.boolean),
        else => return error.TestUnexpectedResult,
    }

    var false_parser = Parser.init(al, "false");
    const false_expr = try false_parser.parse();
    switch (false_expr.*) {
        .literal => |literal| try std.testing.expect(!literal.value.boolean),
        else => return error.TestUnexpectedResult,
    }
}

test "parses string literal contents without quotes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "\"prod\"");
    const expr = try parser.parse();

    switch (expr.*) {
        .literal => |literal| try std.testing.expectEqualStrings("prod", literal.value.string),
        else => return error.TestUnexpectedResult,
    }
}

test "parses a non-boolean identifier as an identifier expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "env");
    const expr = try parser.parse();

    switch (expr.*) {
        .identifier => {},
        else => return error.TestUnexpectedResult,
    }
}

test "rejects tokens after the expression and reports their offset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var parser = Parser.init(arena.allocator(), "true false");
    try std.testing.expectError(error.ParseFailed, parser.parse());
    try std.testing.expect(parser.parse_error != null);
    try std.testing.expectEqual(@as(usize, 5), parser.parse_error.?.offset);
}
