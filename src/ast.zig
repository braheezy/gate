const Token = @import("scan.zig").Token;

const Kind = enum { integer, boolean, string };

pub const Value = union(Kind) {
    integer: i64,
    boolean: bool,
    string: []const u8,
};

pub const Expr = union(Expression) {
    literal: Literal,
    identifier: Identifier,
    unary: Unary,
    binary: Binary,
    logical: Logical,
};

const Expression = enum {
    literal,
    identifier,
    unary,
    binary,
    logical,
};

pub const Literal = struct {
    value: Value,
    token: Token,
};

const Identifier = struct {
    token: Token,
};

const Unary = struct {
    operator: Token,
    operand: *Expr,
};

const Binary = struct {
    left: *Expr,
    operator: Token,
    right: *Expr,
};

pub const Logical = struct {
    left: *Expr,
    operator: Token,
    right: *Expr,
};
