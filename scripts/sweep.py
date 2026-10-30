import os
import sys
import re

FORBIDDEN_TERMS = [
    r"crosshair\s*x",
    r"copyright.*original",
]

def scan_directory(target_dir):
    print(f"[*] Escaneando seguridad anti-plagio en: {target_dir}")
    violations = 0
    for root, _, files in os.walk(target_dir):
        for file in files:
            if file.endswith(('.py', '.js', '.dart', '.md', '.json', '.html', '.css', '.yaml')):
                file_path = os.path.join(root, file)
                try:
                    with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                        for pattern in FORBIDDEN_TERMS:
                            if re.search(pattern, content, re.IGNORECASE):
                                print(f"[!] POSIBLE REFERENCIA EN {file_path}: {pattern}")
                                violations += 1
                except Exception:
                    pass
    if violations > 0:
        print(f"\n[x] Se encontraron {violations} advertencias.")
        sys.exit(1)
    else:
        print("\n[+] ¡Escaneo superado con éxito! Código limpio.")

if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "."
    scan_directory(target)
