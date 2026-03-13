from pathlib import Path


def test_expected_top_level_paths_exist():
    expected = [
        Path("scripts"),
        Path("scripts/setup"),
        Path("config/protected-devices.yaml"),
        Path("config/selected-devices.yaml"),
        Path("artifacts"),
        Path("docs/developer-guide.md"),
        Path("docs/design.md"),
        Path("docs/comparison.md"),
        Path("docs/setup-guide.md"),
        Path("docs/user-guide.md"),
        Path("docs/benchmarking.md"),
    ]
    missing = [p for p in expected if not p.exists()]
    assert not missing, f"Missing paths: {missing}"
