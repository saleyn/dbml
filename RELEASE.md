# Publishing a Release

This project uses automated workflows to manage releases. Follow these steps to publish a new version.

## Process

1. **Update the version** in `mix.exs`:
   ```elixir
   version: "0.4.0"
   ```

2. **Commit the version bump**:
   ```bash
   git add mix.exs
   git commit -m "Bump version to 0.4.0"
   git push origin master
   ```

3. **Automatic tag creation**: The CI workflow automatically creates a git tag based on the project version when:
   - A push is made to the `master` branch
   - The version in `mix.exs` is greater than the max existing git tag

4. **Automatic release publishing**: Once the tag is created, the release workflow automatically:
   - Creates a GitHub release
   - Publishes the package to Hex.pm (only if the tag is greater than the max existing tag)
   - Retires the prior version on Hex.pm as deprecated

## Key Features

- **Version comparison**: Tags are compared using semantic versioning, so `1.10.0` is correctly recognized as greater than `1.9.0`
- **Idempotent publishing**: The release workflow won't publish if the tag is not greater than the max existing tag, preventing accidental downgrades
- **No manual tagging needed**: The CI workflow handles tag creation automatically based on the `mix.exs` version

## Manual Tag Creation (if needed)

If you need to manually create a tag:

```bash
git tag 0.4.0
git push origin 0.4.0
```

This will trigger the release workflow.

## Troubleshooting

- **Tag not created**: Check that the version in `mix.exs` is greater than the max existing git tag
- **Release not published**: Verify the Hex API key is configured in repository secrets (`HEX_API_KEY`)
- **Version mismatch**: Ensure the version in `mix.exs` matches the intended release version (without the `v` prefix)
