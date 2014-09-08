Don't Settle for a List of Strings
==================================

    *"Other tokenizers return lists of strings, which is downright
    barbaric."*
        --- me, now


spaCy splits a string of natural language into a list of lexical types,
which come with a variety of features pre-computed.
Its design makes the right thing easy: your NLP applications will be more
efficient if you use a global vocabulary store, and will probably be more
accurate if you use the features we provide.

Other tokenizers give you a list of strings, which makes the *wrong* thing
easy. The wrong thing is to compute string features and look-up distributional
data on every *token*, instead of every *type*. 

For instance, let's say you're writing an entity tagger, and your feature
functions need to know whether the word you're tagging is lower-cased.  The right
thing is to call string.isalpha() once for every *type* in your vocabulary, instead
of once for every *token* in the text you're tagging.

And the right thing isn't just better, it's *exponentially* better, because of
`Zipf's law <http://en.wikipedia.org/wiki/Zipf's_law>`_.
In a sample of natural language, you can expect to see exponentially fewer types
than tokens.

Because of Zipf's Law, you want to cache all your per-type computations. This
is exactly what spaCy does for you.  Zipf's Law also makes distributional
information a really powerful source of type-based features. It's really handy
to know where a word falls in the language's frequency distribution, especially
compared to variants of the word.  For instance, we might be processing
a Twitter comment that contains the string "nasa". We have little hope of
recognising this as an entity except by noting that the string "NASA" is much
more common, and that both strings are quite rare.

Each spaCy Lexeme comes with a rich, curated set of orthographic and
distributional features.  The exact set of features is language-specific,
to take into account different orthographic conventions and morphological
complexity. It's also easy to define your own features, which should be pure
functions from the string and its distributional data to a string, bool or
real-value.

Finally, spaCy also takes care to get the details right. No unicode problems
here, and indices into the original text are always easy to calculate. You'll
also receive tokens for newlines, tabs and other non-space whitespace, making
it easy to do paragraph and sentence recognition.


Benchmark
---------

The tokenizer itself is also very efficient:

+--------+-------+--------------+--------------+
| System | Time	 | Words/second | Speed Factor |
+--------+-------+--------------+--------------+
| NLTK	 | 6m4s  | 89,000       | 1.00         |
+--------+-------+--------------+--------------+
| spaCy	 | 9.5s	 | 3,093,000	| 38.30        |
+--------+-------+--------------+--------------+

The comparison refers to 30 million words from the English Gigaword, on
a Maxbook Air.  For context, calling string.split() on the data completes in
about 5s.

Pros and Cons
-------------

Pros:

- All tokens come with indices into the original string
- Full unicode support
- Extensible to other languages
- Batch operations computed efficiently in Cython
- Cython API
- numpy interoperability

Cons:

- It's new (released September 2014)
- Security concerns, from memory management
- Higher memory usage (up to 1gb)
- More conceptually complicated
- Tokenization rules expressed in code, not as data

