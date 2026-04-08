Heroku Sentry Log Drain

[mise](https://mise.jdx.dev/) is used for Ruby version management.

## Code style

Ruby is formatted with [gl_rubocop](https://github.com/givelively/gl_rubocop). Run `bin/lint` to automatically format the code.

### Code guidelines:

- Code in a functional way. Avoid mutation (side effects) when you can.
- For service modules, use [functionable gem](https://github.com/bkuhlmann/functionable)
  - Use `conceal` to mark methods as private. It has a `private below here` comment to specify which are private
- Don't mutate arguments
- Don't monkeypatch
- make methods private if possible
- Omit named arguments' values from hashes (ie prefer `{x:, y:}` instead of `{x: x, y: y}`)
- Prefer less code, by character count (excluding whitespace and comments)
- prefer un-abbreviated variable names


## Testing

This project uses Rspec for tests. All business logic should be tested.

- Tests should either: help make the code correct now or prevent bugs in the future. Don't add tests that don't do one of those things.
- Use integration specs for HTTP endpoints
- Avoid testing private methods
- Avoid mocking objects
- Use `context` and `let` to isolate what varies between examples.
  - Each `it` block should live in a `context` that names the condition, with `let` overrides for only what differs in that case. Avoid repeating setup across sibling `it` blocks.
