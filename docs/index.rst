.. spaCy documentation master file, created by
   sphinx-quickstart on Tue Aug 19 16:27:38 2014.
   You can adapt this file completely to your liking, but it should at least
   contain the root `toctree` directive.

spaCy NLP Tokenizer and Lexicon
================================

spaCy splits a string of natural language into a list of references to lexical types:

    >>> from spacy.en import EN
    >>> tokens = EN.tokenize(u"Examples aren't easy, are they?")
    >>> type(tokens[0])
    spacy.word.Lexeme
    >>> tokens[1] is tokens[5]
    True

Other tokenizers return lists of strings, which is
`downright barbaric <guide/overview.html>`__.

License
-------

+------------------+------+
| Non-commercial   | $0   |
+------------------+------+
| Trial commercial | $0   |
+------------------+------+
| Full commercial  | $500 |
+------------------+------+


spaCy is non-free software. Its source is published, but the copyright is
retained by the author (Matthew Honnibal).  Licenses are currently under preparation.

There is currently a gap between the output of academic NLP researchers, and
the needs of a small software companiess. I left academia to try to correct this.

My idea is that non-commercial and trial commercial use should "feel" just like
free software. But, if you do use the code in a commercial product, a small
fixed license-fee will apply, in order to fund development. 

.. toctree::
    :maxdepth: 3
    
    guide/overview.rst
    guide/install.rst

    api/index.rst

    modules/index.rst
