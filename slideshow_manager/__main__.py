from __future__ import annotations

import os

from . import create_app


def main() -> None:
    port = int(os.environ.get("PORT", "8000"))
    app = create_app()
    app.run(host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
