.PHONY: build clean install-dev venv

VENV = .venv
PYTHON = $(VENV)/bin/python
PIP = $(VENV)/bin/pip

# Create virtual environment
venv:
	python -m venv $(VENV)
	$(PIP) install -r requirements-dev.txt

# Build the standalone binary
build: venv
	$(VENV)/bin/pyinstaller --clean fetch-usage.spec
	@echo "Binary created: dist/claude-usage"

# Install development dependencies (into venv)
install-dev: venv

# Clean build artifacts
clean:
	rm -rf build dist __pycache__ *.egg-info
	rm -rf .eggs .pytest_cache

# Clean everything including venv
clean-all: clean
	rm -rf $(VENV)
