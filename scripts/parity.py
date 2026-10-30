import sys
import json

def calculate_parity(manifest_path):
    print(f"[*] Evaluando paridad con: {manifest_path}")
    try:
        with open(manifest_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        total = len(data.get("features", []))
        if total == 0:
            return
        completed = sum(1 for feat in data["features"] if feat.get("status") == "completed")
        percentage = (completed / total) * 100
        print(f"\n[📊] Paridad Funcional: {percentage:.2f}% ({completed}/{total} completadas)")
    except Exception as e:
        print(f"[x] Error: {e}")

if __name__ == "__main__":
    manifest = sys.argv[1] if len(sys.argv) > 1 else "features.json"
    calculate_parity(manifest)
