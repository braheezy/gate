# gate

A CLI that parses and evaluates a small policy language against `key=value` facts.

```bash
gate 'env == "prod" && replicas >= 3 && !maintenance' \
  env=prod replicas=4 maintenance=false
```

Exit `0` when true, `1` when false, and `2` for syntax or type errors.

## Usage

Clone and build with Zig.

```
git clone https://github.com/braheezy/gate.git
cd gate
zig build
./zig-out/bin/gate
```
