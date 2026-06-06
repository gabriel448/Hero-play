"""Gera os avatares Lottie (placeholders) dos perfis em assets/avatars/.

Cada avatar e um circulo colorido de fundo + uma forma geometrica em creme.
Sao ESTATICOS de proposito: a animacao de "respiracao" (escala) cortava as
beiradas do circulo e congelava o icone ampliado ao trocar a selecao. As
animacoes (entrada na home, crescer ao selecionar) ficam no nivel do widget.

Sao Lottie v5 validos, renderizados em runtime pelo pacote `lottie` do Flutter.
Rode com:  python tool/gerar_avatares.py
"""
import json
import os

CREME = [0.961, 0.945, 0.925, 1]  # AppColors.textPrimary

# (chave, [r,g,b] 0..1 do fundo, forma)
AVATARES = [
    ("ember",  [0.898, 0.224, 0.208], "estrela"),
    ("reef",   [0.149, 0.651, 0.604], "anel"),
    ("citrus", [0.851, 0.635, 0.243], "quadrado"),
    ("grape",  [0.584, 0.459, 0.804], "triangulo"),
    ("fern",   [0.482, 0.651, 0.561], "circulo"),
    ("tide",   [0.310, 0.549, 0.784], "hexagono"),
]


def tr_centro():
    return {
        "ty": "tr",
        "p": {"a": 0, "k": [100, 100]},
        "a": {"a": 0, "k": [0, 0]},
        "s": {"a": 0, "k": [100, 100]},
        "r": {"a": 0, "k": 0},
        "o": {"a": 0, "k": 100},
    }


def fill(cor):
    return {"ty": "fl", "c": {"a": 0, "k": cor}, "o": {"a": 0, "k": 100}, "r": 1}


def forma_fg(tipo):
    """Devolve (lista_de_itens_de_forma, usa_stroke)."""
    if tipo == "estrela":
        return [{"ty": "sr", "sy": 1, "pt": {"a": 0, "k": 5},
                 "p": {"a": 0, "k": [0, 0]}, "r": {"a": 0, "k": 0},
                 "ir": {"a": 0, "k": 27}, "is": {"a": 0, "k": 0},
                 "or": {"a": 0, "k": 62}, "os": {"a": 0, "k": 0}}], False
    if tipo == "anel":
        return [{"ty": "el", "s": {"a": 0, "k": [98, 98]},
                 "p": {"a": 0, "k": [0, 0]}}], True
    if tipo == "quadrado":
        return [{"ty": "rr", "s": {"a": 0, "k": [98, 98]},
                 "p": {"a": 0, "k": [0, 0]}, "r": {"a": 0, "k": 28}}], False
    if tipo == "triangulo":
        return [{"ty": "sr", "sy": 2, "pt": {"a": 0, "k": 3},
                 "p": {"a": 0, "k": [0, 6]}, "r": {"a": 0, "k": 0},
                 "or": {"a": 0, "k": 64}, "os": {"a": 0, "k": 10}}], False
    if tipo == "circulo":
        return [{"ty": "el", "s": {"a": 0, "k": [92, 92]},
                 "p": {"a": 0, "k": [0, 0]}}], False
    if tipo == "hexagono":
        return [{"ty": "sr", "sy": 2, "pt": {"a": 0, "k": 6},
                 "p": {"a": 0, "k": [0, 0]}, "r": {"a": 0, "k": 0},
                 "or": {"a": 0, "k": 60}, "os": {"a": 0, "k": 8}}], False
    raise ValueError(tipo)


def grupo_fg(tipo):
    formas, usa_stroke = forma_fg(tipo)
    estilo = (
        {"ty": "st", "c": {"a": 0, "k": CREME}, "o": {"a": 0, "k": 100},
         "w": {"a": 0, "k": 15}, "lc": 2, "lj": 1}
        if usa_stroke else fill(CREME)
    )
    return {"ty": "gr", "nm": "fg", "it": formas + [estilo, tr_centro()]}


def grupo_bg(cor):
    return {"ty": "gr", "nm": "bg", "it": [
        {"ty": "el", "s": {"a": 0, "k": [200, 200]}, "p": {"a": 0, "k": [0, 0]}},
        fill(cor),
        tr_centro(),
    ]}


def avatar(chave, cor, tipo):
    return {
        "v": "5.7.0", "fr": 60, "ip": 0, "op": 90, "w": 200, "h": 200,
        "nm": chave, "ddd": 0, "assets": [],
        "layers": [{
            "ddd": 0, "ind": 1, "ty": 4, "nm": "av", "sr": 1, "ao": 0,
            "ks": {
                "o": {"a": 0, "k": 100},
                "r": {"a": 0, "k": 0},
                "p": {"a": 0, "k": [100, 100, 0]},
                "a": {"a": 0, "k": [100, 100, 0]},
                "s": {"a": 0, "k": [100, 100, 100]},  # estatico (sem respiracao)
            },
            # foreground primeiro = renderiza por cima do background.
            "shapes": [grupo_fg(tipo), grupo_bg(cor)],
            "ip": 0, "op": 90, "st": 0, "bm": 0,
        }],
    }


def main():
    raiz = os.path.join(os.path.dirname(__file__), "..", "assets", "avatars")
    os.makedirs(raiz, exist_ok=True)
    for chave, cor, tipo in AVATARES:
        caminho = os.path.join(raiz, f"{chave}.json")
        with open(caminho, "w", encoding="utf-8") as f:
            json.dump(avatar(chave, cor, tipo), f, separators=(",", ":"))
        print("ok", caminho)


if __name__ == "__main__":
    main()
