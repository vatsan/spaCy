IDS = {
    "": NULL_ATTR,
    "IS_ALPHA": IS_ALPHA,
    "IS_ASCII": IS_ASCII,
    "IS_DIGIT": IS_DIGIT,
    "IS_LOWER": IS_LOWER,
    "IS_PUNCT": IS_PUNCT,
    "IS_SPACE": IS_SPACE,
    "IS_TITLE": IS_TITLE,
    "IS_UPPER": IS_UPPER,
    "LIKE_URL": LIKE_URL,
    "LIKE_NUM": LIKE_NUM,
    "LIKE_EMAIL": LIKE_EMAIL,
    "IS_STOP": IS_STOP,
    "IS_OOV": IS_OOV,

    "FLAG14": FLAG14,
    "FLAG15": FLAG15,
    "FLAG16": FLAG16,
    "FLAG17": FLAG17,
    "FLAG18": FLAG18,
    "FLAG19": FLAG19,
    "FLAG20": FLAG20,
    "FLAG21": FLAG21,
    "FLAG22": FLAG22,
    "FLAG23": FLAG23,
    "FLAG24": FLAG24,
    "FLAG25": FLAG25,
    "FLAG26": FLAG26,
    "FLAG27": FLAG27,
    "FLAG28": FLAG28,
    "FLAG29": FLAG29,
    "FLAG30": FLAG30,
    "FLAG31": FLAG31,
    "FLAG32": FLAG32,
    "FLAG33": FLAG33,
    "FLAG34": FLAG34,
    "FLAG35": FLAG35,
    "FLAG36": FLAG36,
    "FLAG37": FLAG37,
    "FLAG38": FLAG38,
    "FLAG39": FLAG39,
    "FLAG40": FLAG40,
    "FLAG41": FLAG41,
    "FLAG42": FLAG42,
    "FLAG43": FLAG43,
    "FLAG44": FLAG44,
    "FLAG45": FLAG45,
    "FLAG46": FLAG46,
    "FLAG47": FLAG47,
    "FLAG48": FLAG48,
    "FLAG49": FLAG49,
    "FLAG50": FLAG50,
    "FLAG51": FLAG51,
    "FLAG52": FLAG52,
    "FLAG53": FLAG53,
    "FLAG54": FLAG54,
    "FLAG55": FLAG55,
    "FLAG56": FLAG56,
    "FLAG57": FLAG57,
    "FLAG58": FLAG58,
    "FLAG59": FLAG59,
    "FLAG60": FLAG60,
    "FLAG61": FLAG61,
    "FLAG62": FLAG62,
    "FLAG63": FLAG63,

    "ID": ID,
    "ORTH": ORTH,
    "LOWER": LOWER,
    "NORM": NORM,
    "SHAPE": SHAPE,
    "PREFIX": PREFIX,
    "SUFFIX": SUFFIX,

    "LENGTH": LENGTH,
    "CLUSTER": CLUSTER,
    "LEMMA": LEMMA,
    "POS": POS,
    "TAG": TAG,
    "DEP": DEP,
    "ENT_IOB": ENT_IOB,
    "ENT_TYPE": ENT_TYPE,
    "HEAD": HEAD,
    "SPACY": SPACY,
    "PROB": PROB,
}

# ATTR IDs, in order of the symbol
NAMES = [key for key, value in sorted(IDS.items(), key=lambda item: item[1])]
