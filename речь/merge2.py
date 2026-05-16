import os

# === НАСТРОЙКИ ===
OUTPUT_FILE = "_merged.txt"
EXTENSIONS = ".asm"
# EXTENSIONS = [".md", ".html", ".css"]
# None = берёт всё подряд, кроме самого себя
# =================

script_path = os.path.abspath(__file__)
script_dir = os.path.dirname(script_path)
script_name = os.path.basename(script_path)
output_path = os.path.join(script_dir, OUTPUT_FILE)

with open(output_path, "w", encoding="utf-8") as out:
    for root, dirs, files in os.walk(script_dir):
        # вырезаем скрытые папки
        dirs[:] = [d for d in dirs if not d.startswith(".")]

        for filename in sorted(files):
            # скрытые файлы нахуй
            if filename.startswith("."):
                continue

            full_path = os.path.join(root, filename)

            if full_path in (script_path, output_path):
                continue

            if EXTENSIONS:
                if not any(filename.lower().endswith(ext) for ext in EXTENSIONS):
                    continue

            full_path_win = os.path.abspath(full_path).replace("/", "\\")

            try:
                with open(full_path, "r", encoding="utf-8") as f:
                    content = f.read()
            except Exception as e:
                out.write(f"{full_path_win}\n")
                out.write(f"[НЕ СМОГ ПРОЧИТАТЬ ФАЙЛ: {e}]\n\n\n")
                continue

            out.write(f"{full_path_win}\n\n")
            out.write(content)
            out.write("\n\n\n")

print("Готово. Всё слеплено в", OUTPUT_FILE)
