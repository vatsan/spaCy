from libc.string cimport memcpy
from cpython.mem cimport PyMem_Malloc, PyMem_Free
# Compiler crashes on memory view coercion without this. Should report bug.
from cython.view cimport array as cvarray
cimport numpy as np
np.import_array()

import numpy


from ..lexeme cimport Lexeme
from .. import parts_of_speech

from ..attrs cimport LEMMA
from ..attrs cimport ID, ORTH, NORM, LOWER, SHAPE, PREFIX, SUFFIX, LENGTH, CLUSTER
from ..attrs cimport POS, LEMMA, TAG, DEP
from ..parts_of_speech cimport CONJ, PUNCT

from ..attrs cimport IS_ALPHA, IS_ASCII, IS_DIGIT, IS_LOWER, IS_PUNCT, IS_SPACE
from ..attrs cimport IS_TITLE, IS_UPPER, LIKE_URL, LIKE_NUM, LIKE_EMAIL, IS_STOP
from ..attrs cimport IS_OOV

from ..lexeme cimport Lexeme


cdef class Token:
    """An individual token --- i.e. a word, a punctuation symbol, etc.  Created
    via Doc.__getitem__ and Doc.__iter__.
    """
    def __cinit__(self, Vocab vocab, Doc doc, int offset):
        self.vocab = vocab
        self.doc = doc
        self.c = &self.doc.data[offset]
        self.i = offset
        self.array_len = doc.length

    def __len__(self):
        return self.c.lex.length

    def __unicode__(self):
        return self.string

    def __str__(self):
        return self.string

    cpdef bint check_flag(self, attr_id_t flag_id) except -1:
        return Lexeme.c_check_flag(self.c.lex, flag_id)

    def nbor(self, int i=1):
        return self.doc[self.i+i]

    def similarity(self, other):
        if self.vector_norm == 0 or other.vector_norm == 0:
            return 0.0
        return numpy.dot(self.vector, other.vector) / (self.vector_norm * other.vector_norm)

    property lex_id:
        def __get__(self):
            return self.c.lex.id

    property string:
        def __get__(self):
            cdef unicode orth = self.vocab.strings[self.c.lex.orth]
            if self.c.spacy:
                return orth + u' '
            else:
                return orth

    property text:
        def __get__(self):
            return self.orth_

    property text_with_ws:
        def __get__(self):
            cdef unicode orth = self.vocab.strings[self.c.lex.orth]
            if self.c.spacy:
                return orth + u' '
            else:
                return orth

    property prob:
        def __get__(self):
            return self.c.lex.prob

    property idx:
        def __get__(self):
            return self.c.idx

    property cluster:
        def __get__(self):
            return self.c.lex.cluster

    property orth:
        def __get__(self):
            return self.c.lex.orth

    property lower:
        def __get__(self):
            return self.c.lex.lower

    property norm:
        def __get__(self):
            return self.c.lex.norm

    property shape:
        def __get__(self):
            return self.c.lex.shape

    property prefix:
        def __get__(self):
            return self.c.lex.prefix

    property suffix:
        def __get__(self):
            return self.c.lex.suffix

    property lemma:
        def __get__(self):
            return self.c.lemma

    property pos:
        def __get__(self):
            return self.c.pos

    property tag:
        def __get__(self):
            return self.c.tag

    property dep:
        def __get__(self):
            return self.c.dep

    property has_vector:
        def __get__(self):
            cdef int i
            for i in range(self.vocab.vectors_length):
                if self.c.lex.repvec[i] != 0:
                    return True
            else:
                return False

    property vector:
        def __get__(self):
            cdef int length = self.vocab.vectors_length
            if length == 0:
                raise ValueError(
                    "Word vectors set to length 0. This may be because the "
                    "data is not installed. If you haven't already, run"
                    "\npython -m spacy.en.download all\n"
                    "to install the data."
                )
            repvec_view = <float[:length,]>self.c.lex.repvec
            return numpy.asarray(repvec_view)

    property repvec:
        def __get__(self):
            return self.vector

    property vector_norm:
        def __get__(self):
            return self.c.lex.l2_norm

    property n_lefts:
        def __get__(self):
            cdef int n = 0
            cdef const TokenC* ptr = self.c - self.i
            while ptr != self.c:
                if ptr + ptr.head == self.c:
                    n += 1
                ptr += 1
            return n

    property n_rights:
        def __get__(self):
            cdef int n = 0
            cdef const TokenC* ptr = self.c + (self.array_len - self.i)
            while ptr != self.c:
                if ptr + ptr.head == self.c:
                    n += 1
                ptr -= 1
            return n

    property lefts:
        def __get__(self):
            """The leftward immediate children of the word, in the syntactic
            dependency parse.
            """
            cdef const TokenC* ptr = self.c - (self.i - self.c.l_edge)
            while ptr < self.c:
                # If this head is still to the right of us, we can skip to it
                # No token that's between this token and this head could be our
                # child.
                if (ptr.head >= 1) and (ptr + ptr.head) < self.c:
                    ptr += ptr.head

                elif ptr + ptr.head == self.c:
                    yield self.doc[ptr - (self.c - self.i)]
                    ptr += 1
                else:
                    ptr += 1

    property rights:
        def __get__(self):
            """The rightward immediate children of the word, in the syntactic
            dependency parse."""
            cdef const TokenC* ptr = self.c + (self.c.r_edge - self.i)
            tokens = []
            while ptr > self.c:
                # If this head is still to the right of us, we can skip to it
                # No token that's between this token and this head could be our
                # child.
                if (ptr.head < 0) and ((ptr + ptr.head) > self.c):
                    ptr += ptr.head
                elif ptr + ptr.head == self.c:
                    tokens.append(self.doc[ptr - (self.c - self.i)])
                    ptr -= 1
                else:
                    ptr -= 1
            tokens.reverse()
            for t in tokens:
                yield t

    property children:
        def __get__(self):
            yield from self.lefts
            yield from self.rights

    property subtree:
        def __get__(self):
            for word in self.lefts:
                yield from word.subtree
            yield self
            for word in self.rights:
                yield from word.subtree

    property left_edge:
        def __get__(self):
            return self.doc[self.c.l_edge]

    property right_edge:
        def __get__(self):
            return self.doc[self.c.r_edge]

    property head:
        def __get__(self):
            """The token predicted by the parser to be the head of the current token."""
            return self.doc[self.i + self.c.head]

    property conjuncts:
        def __get__(self):
            """Get a list of conjoined words."""
            cdef Token word
            conjuncts = []
            if self.dep_ != 'conj':
                for word in self.rights:
                    if word.dep_ == 'conj':
                        yield word
                        yield from word.conjuncts
                        conjuncts.append(word)
                        conjuncts.extend(word.conjuncts)

    property ent_type:
        def __get__(self):
            return self.c.ent_type

    property ent_iob:
        def __get__(self):
            return self.c.ent_iob

    property ent_type_:
        def __get__(self):
            return self.vocab.strings[self.c.ent_type]

    property ent_iob_:
        def __get__(self):
            iob_strings = ('', 'I', 'O', 'B')
            return iob_strings[self.c.ent_iob]

    property whitespace_:
        def __get__(self):
            return ' ' if self.c.spacy else ''

    property orth_:
        def __get__(self):
            return self.vocab.strings[self.c.lex.orth]

    property lower_:
        def __get__(self):
            return self.vocab.strings[self.c.lex.lower]

    property norm_:
        def __get__(self):
            return self.vocab.strings[self.c.lex.norm]

    property shape_:
        def __get__(self):
            return self.vocab.strings[self.c.lex.shape]

    property prefix_:
        def __get__(self):
            return self.vocab.strings[self.c.lex.prefix]

    property suffix_:
        def __get__(self):
            return self.vocab.strings[self.c.lex.suffix]

    property lemma_:
        def __get__(self):
            return self.vocab.strings[self.c.lemma]

    property pos_:
        def __get__(self):
            return parts_of_speech.NAMES[self.c.pos]

    property tag_:
        def __get__(self):
            return self.vocab.strings[self.c.tag]

    property dep_:
        def __get__(self):
            return self.vocab.strings[self.c.dep]

    property is_oov:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, IS_OOV)

    property is_stop:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, IS_STOP)

    property is_alpha:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, IS_ALPHA)

    property is_ascii:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, IS_ASCII)

    property is_digit:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, IS_DIGIT)

    property is_lower:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, IS_LOWER)

    property is_title:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, IS_TITLE)

    property is_punct:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, IS_PUNCT)

    property is_space: 
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, IS_SPACE)

    property like_url:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, LIKE_URL)

    property like_num:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, LIKE_NUM)

    property like_email:
        def __get__(self): return Lexeme.c_check_flag(self.c.lex, LIKE_EMAIL)
