const std = @import("std");
pub const TokenType = enum(u8) {
    // Single-character tokens.
    LEFT_PAREN,
    RIGHT_PAREN,
    // One or two character tokens.
    BANG,
    BANG_EQUAL,
    EQUAL_EQUAL,
    GREATER,
    GREATER_EQUAL,
    LESS,
    LESS_EQUAL,
    AND_AND,
    OR_OR,
    // Literals.
    IDENTIFIER,
    STRING,
    NUMBER,

    ERROR,
    EOF,
};

pub const Token = struct {
    token_type: TokenType,
    start_pos: usize,
    end_pos: usize,
    error_message: ?[]const u8 = null,
};

pub const Scanner = struct {
    source: []const u8,
    start: usize,
    current: usize,

    pub fn init(source: []const u8) Scanner {
        return Scanner{ .source = source, .start = 0, .current = 0 };
    }

    pub fn scanToken(self: *Scanner) Token {
        self.skipWhitespace();
        self.start = self.current;
        if (self.isAtEnd()) return self.makeToken(.EOF);

        const c = self.advance();
        if (isAlpha(c)) return self.identifier();
        if (isDigit(c)) return self.number();
        switch (c) {
            '(' => return self.makeToken(.LEFT_PAREN),
            ')' => return self.makeToken(.RIGHT_PAREN),
            '!' => return self.makeToken(if (self.match('=')) .BANG_EQUAL else .BANG),
            '=' => return self.makeToken(if (self.match('=')) .EQUAL_EQUAL else return self.errorToken("Unexpected character.")),
            '<' => return self.makeToken(if (self.match('=')) .LESS_EQUAL else .LESS),
            '>' => return self.makeToken(if (self.match('=')) .GREATER_EQUAL else .GREATER),
            '"' => return self.string(),
            '|' => return self.makeToken(if (self.match('|')) .OR_OR else return self.errorToken("Unexpected character.")),
            '&' => return self.makeToken(if (self.match('&')) .AND_AND else return self.errorToken("Unexpected character.")),
            else => return self.errorToken("Unexpected character."),
        }
    }

    pub fn advance(self: *Scanner) u8 {
        const c = self.source[self.current];
        self.current += 1;
        return c;
    }

    pub fn fromToken(self: Scanner, token: Token) []const u8 {
        return self.source[token.start_pos..token.end_pos];
    }

    fn isDigit(c: u8) bool {
        return c >= '0' and c <= '9';
    }

    fn isAlpha(c: u8) bool {
        return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_';
    }

    fn isAtEnd(self: *Scanner) bool {
        return self.current >= self.source.len;
    }

    fn match(self: *Scanner, expected: u8) bool {
        if (self.isAtEnd()) return false;
        if (self.source[self.current] != expected) return false;
        self.current += 1;
        return true;
    }

    fn skipWhitespace(self: *Scanner) void {
        while (true) {
            const c = self.peek();
            switch (c) {
                ' ', '\r', '\t', '\n' => _ = self.advance(),
                else => return,
            }
        }
    }

    fn identifier(self: *Scanner) Token {
        while (isAlpha(self.peek()) or isDigit(self.peek())) _ = self.advance();

        return self.makeToken(TokenType.IDENTIFIER);
    }

    fn number(self: *Scanner) Token {
        while (isDigit(self.peek())) _ = self.advance();

        return self.makeToken(TokenType.NUMBER);
    }

    fn string(self: *Scanner) Token {
        while (self.peek() != '"' and !self.isAtEnd()) {
            _ = self.advance();
        }

        if (self.isAtEnd()) return self.errorToken("Unterminated string.");

        // the closing quote
        _ = self.advance();
        return self.makeToken(TokenType.STRING);
    }

    fn peek(self: *Scanner) u8 {
        if (self.current >= self.source.len) return 0;
        return self.source[self.current];
    }

    fn peekNext(self: *Scanner) u8 {
        if (self.isAtEnd()) return 0;
        if (self.current + 1 >= self.source.len) return 0;
        return self.source[self.current + 1];
    }

    fn makeToken(self: *Scanner, token_type: TokenType) Token {
        return Token{
            .token_type = token_type,
            .start_pos = self.start,
            .end_pos = self.current,
        };
    }

    fn errorToken(self: *Scanner, message: []const u8) Token {
        return Token{
            .token_type = .ERROR,
            .error_message = message,
            .start_pos = self.start,
            .end_pos = self.current,
        };
    }
};

test "scans identifiers and numbers with byte spans" {
    var s = Scanner.init("env replicas42 123");

    const env = s.scanToken();
    try std.testing.expectEqual(TokenType.IDENTIFIER, env.token_type);
    try std.testing.expectEqual(@as(usize, 0), env.start_pos);
    try std.testing.expectEqual(@as(usize, 3), env.end_pos);

    const replicas = s.scanToken();
    try std.testing.expectEqual(TokenType.IDENTIFIER, replicas.token_type);
    try std.testing.expectEqual(@as(usize, 4), replicas.start_pos);
    try std.testing.expectEqual(@as(usize, 14), replicas.end_pos);

    const number = s.scanToken();
    try std.testing.expectEqual(TokenType.NUMBER, number.token_type);
    try std.testing.expectEqual(@as(usize, 15), number.start_pos);
    try std.testing.expectEqual(@as(usize, 18), number.end_pos);

    try std.testing.expectEqual(TokenType.EOF, s.scanToken().token_type);
}

test "scans supported operators and parentheses" {
    var s = Scanner.init("( ) ! != == < <= > >= && ||");
    const expected = [_]TokenType{
        .LEFT_PAREN, .RIGHT_PAREN, .BANG,    .BANG_EQUAL,    .EQUAL_EQUAL,
        .LESS,       .LESS_EQUAL,  .GREATER, .GREATER_EQUAL, .AND_AND,
        .OR_OR,
    };

    for (expected) |token_type| {
        try std.testing.expectEqual(token_type, s.scanToken().token_type);
    }
    try std.testing.expectEqual(TokenType.EOF, s.scanToken().token_type);
}

test "scans quoted strings and preserves their spans" {
    var s = Scanner.init("\"prod\"");
    const token = s.scanToken();

    try std.testing.expectEqual(TokenType.STRING, token.token_type);
    try std.testing.expectEqual(@as(usize, 0), token.start_pos);
    try std.testing.expectEqual(@as(usize, 6), token.end_pos);
}

test "true and false are initially identifiers" {
    var s = Scanner.init("true false");

    try std.testing.expectEqual(TokenType.IDENTIFIER, s.scanToken().token_type);
    try std.testing.expectEqual(TokenType.IDENTIFIER, s.scanToken().token_type);
}

test "rejects unsupported single character operators" {
    var s = Scanner.init("= & |");

    for ([_]usize{ 0, 2, 4 }) |offset| {
        const token = s.scanToken();
        try std.testing.expectEqual(TokenType.ERROR, token.token_type);
        try std.testing.expectEqual(offset, token.start_pos);
        try std.testing.expectEqual(offset + 1, token.end_pos);
        try std.testing.expect(token.error_message != null);
    }
}

test "reports unterminated strings" {
    var s = Scanner.init("\"prod");
    const token = s.scanToken();

    try std.testing.expectEqual(TokenType.ERROR, token.token_type);
    try std.testing.expectEqual(@as(usize, 0), token.start_pos);
    try std.testing.expectEqual(@as(usize, 5), token.end_pos);
    try std.testing.expectEqualStrings("Unterminated string.", token.error_message.?);
}
