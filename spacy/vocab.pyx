from __future__ import unicode_literals

from libc.stdio cimport fopen, fclose, fread, fwrite, FILE
from libc.string cimport memset
from libc.stdint cimport int32_t
from libc.stdint cimport uint64_t

import bz2
from os import path
import io
import math
import json
import tempfile

from .lexeme cimport EMPTY_LEXEME
from .lexeme cimport Lexeme
from .strings cimport hash_string
from .orth cimport word_shape
from .typedefs cimport attr_t
from .cfile cimport CFile
from .lemmatizer import Lemmatizer

from . import attrs
from . import symbols

from cymem.cymem cimport Address
from . import util
from .serialize.packer cimport Packer
from .attrs cimport PROB

try:
    import copy_reg
except ImportError:
    import copyreg as copy_reg


DEF MAX_VEC_SIZE = 100000


cdef float[MAX_VEC_SIZE] EMPTY_VEC
memset(EMPTY_VEC, 0, sizeof(EMPTY_VEC))
memset(&EMPTY_LEXEME, 0, sizeof(LexemeC))
EMPTY_LEXEME.repvec = EMPTY_VEC


cdef class Vocab:
    '''A map container for a language's LexemeC structs.
    '''
    @classmethod
    def from_dir(cls, data_dir, get_lex_attr=None):
        if not path.exists(data_dir):
            raise IOError("Directory %s not found -- cannot load Vocab." % data_dir)
        if not path.isdir(data_dir):
            raise IOError("Path %s is a file, not a dir -- cannot load Vocab." % data_dir)

        tag_map = json.load(open(path.join(data_dir, 'tag_map.json')))
        lemmatizer = Lemmatizer.from_dir(path.join(data_dir, '..'))
        if path.exists(path.join(data_dir, 'serializer.json')):
            serializer_freqs = json.load(open(path.join(data_dir, 'serializer.json')))
        else:
            serializer_freqs = None
        cdef Vocab self = cls(get_lex_attr=get_lex_attr, tag_map=tag_map,
                              lemmatizer=lemmatizer, serializer_freqs=serializer_freqs)

        self.load_lexemes(path.join(data_dir, 'strings.txt'), path.join(data_dir, 'lexemes.bin'))
        if path.exists(path.join(data_dir, 'vec.bin')):
            self.vectors_length = self.load_vectors_from_bin_loc(path.join(data_dir, 'vec.bin'))
        return self

    def __init__(self, get_lex_attr=None, tag_map=None, lemmatizer=None, serializer_freqs=None):
        if tag_map is None:
            tag_map = {}
        if lemmatizer is None:
            lemmatizer = Lemmatizer({}, {}, {})
        self.mem = Pool()
        self._by_hash = PreshMap()
        self._by_orth = PreshMap()
        self.strings = StringStore()
        # Load strings in a special order, so that we have an onset number for
        # the vocabulary. This way, when words are added in order, the orth ID
        # is the frequency rank of the word, plus a certain offset. The structural
        # strings are loaded first, because the vocab is open-class, and these
        # symbols are closed class.
        for name in symbols.NAMES + list(sorted(tag_map.keys())):
            if name:
                _ = self.strings[name]
        self.get_lex_attr = get_lex_attr
        self.morphology = Morphology(self.strings, tag_map, lemmatizer)
        self.serializer_freqs = serializer_freqs
        
        self.length = 1
        self._serializer = None
    
    property serializer:
        def __get__(self):
            if self._serializer is None:
                freqs = []
                self._serializer = Packer(self, self.serializer_freqs)
            return self._serializer

    def __len__(self):
        """The current number of lexemes stored."""
        return self.length

    def __reduce__(self):
        # TODO: Dump vectors
        tmp_dir = tempfile.mkdtemp()
        lex_loc = path.join(tmp_dir, 'lexemes.bin')
        str_loc = path.join(tmp_dir, 'strings.txt')
        vec_loc = path.join(self.data_dir, 'vec.bin') if self.data_dir is not None else None

        self.dump(lex_loc)
        self.strings.dump(str_loc)
        
        state = (str_loc, lex_loc, vec_loc, self.morphology, self.get_lex_attr,
                 self.serializer_freqs, self.data_dir)
        return (unpickle_vocab, state, None, None)

    cdef const LexemeC* get(self, Pool mem, unicode string) except NULL:
        '''Get a pointer to a LexemeC from the lexicon, creating a new Lexeme
        if necessary, using memory acquired from the given pool.  If the pool
        is the lexicon's own memory, the lexeme is saved in the lexicon.'''
        if string == u'':
            return &EMPTY_LEXEME
        cdef LexemeC* lex
        cdef hash_t key = hash_string(string)
        lex = <LexemeC*>self._by_hash.get(key)
        cdef size_t addr
        if lex != NULL:
            if lex.orth != self.strings[string]:
                raise LookupError.mismatched_strings(
                    lex.orth, self.strings[lex.orth], string)
            return lex
        else:
            return self._new_lexeme(mem, string)

    cdef const LexemeC* get_by_orth(self, Pool mem, attr_t orth) except NULL:
        '''Get a pointer to a LexemeC from the lexicon, creating a new Lexeme
        if necessary, using memory acquired from the given pool.  If the pool
        is the lexicon's own memory, the lexeme is saved in the lexicon.'''
        if orth == 0:
            return &EMPTY_LEXEME
        cdef LexemeC* lex
        lex = <LexemeC*>self._by_orth.get(orth)
        if lex != NULL:
            return lex
        else:
            return self._new_lexeme(mem, self.strings[orth])

    cdef const LexemeC* _new_lexeme(self, Pool mem, unicode string) except NULL:
        cdef hash_t key
        cdef bint is_oov = mem is not self.mem
        if len(string) < 3:
            mem = self.mem
        lex = <LexemeC*>mem.alloc(sizeof(LexemeC), 1)
        lex.orth = self.strings[string]
        lex.length = len(string)
        lex.id = self.length
        lex.repvec = <float*>mem.alloc(self.vectors_length, sizeof(float))
        if self.get_lex_attr is not None:
            for attr, func in self.get_lex_attr.items():
                value = func(string)
                if isinstance(value, unicode):
                    value = self.strings[value]
                if attr == PROB:
                    lex.prob = value
                else:
                    Lexeme.set_struct_attr(lex, attr, value)
        if is_oov:
            lex.id = 0
        else:
            key = hash_string(string)
            self._add_lex_to_vocab(key, lex)
        assert lex != NULL, string
        return lex

    cdef int _add_lex_to_vocab(self, hash_t key, const LexemeC* lex) except -1:
        self._by_hash.set(key, <void*>lex)
        self._by_orth.set(lex.orth, <void*>lex)
        self.length += 1

    def __iter__(self):
        cdef attr_t orth
        cdef size_t addr
        for orth, addr in self._by_orth.items():
            yield Lexeme(self, orth)

    def __getitem__(self,  id_or_string):
        '''Retrieve a lexeme, given an int ID or a unicode string.  If a previously
        unseen unicode string is given, a new lexeme is created and stored.

        Args:
            id_or_string (int or unicode):
              The integer ID of a word, or its unicode string.  If an int >= Lexicon.size,
              IndexError is raised. If id_or_string is neither an int nor a unicode string,
              ValueError is raised.

        Returns:
            lexeme (Lexeme):
              An instance of the Lexeme Python class, with data copied on
              instantiation.
        '''
        cdef attr_t orth
        if type(id_or_string) == unicode:
            orth = self.strings[id_or_string]
        else:
            orth = id_or_string
        return Lexeme(self, orth)

    cdef const TokenC* make_fused_token(self, substrings) except NULL:
        cdef int i
        tokens = <TokenC*>self.mem.alloc(len(substrings) + 1, sizeof(TokenC))
        for i, props in enumerate(substrings):
            token = &tokens[i]
            # Set the special tokens up to have morphology and lemmas if
            # specified, otherwise use the part-of-speech tag (if specified)
            token.lex = <LexemeC*>self.get(self.mem, props['F'])
            if 'pos' in props:
                self.morphology.assign_tag(token, props['pos'])
            if 'L' in props:
                tokens[i].lemma = self.strings[props['L']]
            for feature, value in props.get('morph', {}).items():
                self.morphology.assign_feature(&token.morph, feature, value)
        return tokens
    
    def dump(self, loc):
        if path.exists(loc):
            assert not path.isdir(loc)
        cdef bytes bytes_loc = loc.encode('utf8') if type(loc) == unicode else loc

        cdef CFile fp = CFile(bytes_loc, 'wb')
        cdef size_t st
        cdef size_t addr
        cdef hash_t key
        for key, addr in self._by_hash.items():
            lexeme = <LexemeC*>addr
            fp.write_from(&lexeme.orth, sizeof(lexeme.orth), 1)
            fp.write_from(&lexeme.flags, sizeof(lexeme.flags), 1)
            fp.write_from(&lexeme.id, sizeof(lexeme.id), 1)
            fp.write_from(&lexeme.length, sizeof(lexeme.length), 1)
            fp.write_from(&lexeme.orth, sizeof(lexeme.orth), 1)
            fp.write_from(&lexeme.lower, sizeof(lexeme.lower), 1)
            fp.write_from(&lexeme.norm, sizeof(lexeme.norm), 1)
            fp.write_from(&lexeme.shape, sizeof(lexeme.shape), 1)
            fp.write_from(&lexeme.prefix, sizeof(lexeme.prefix), 1)
            fp.write_from(&lexeme.suffix, sizeof(lexeme.suffix), 1)
            fp.write_from(&lexeme.cluster, sizeof(lexeme.cluster), 1)
            fp.write_from(&lexeme.prob, sizeof(lexeme.prob), 1)
            fp.write_from(&lexeme.sentiment, sizeof(lexeme.sentiment), 1)
            fp.write_from(&lexeme.l2_norm, sizeof(lexeme.l2_norm), 1)
        fp.close()

    def load_lexemes(self, strings_loc, loc):
        self.strings.load(strings_loc)
        if not path.exists(loc):
            raise IOError('LexemeCs file not found at %s' % loc)
        fp = CFile(loc, 'rb')
        cdef LexemeC* lexeme
        cdef hash_t key
        cdef unicode py_str
        cdef attr_t orth
        assert sizeof(orth) == sizeof(lexeme.orth)
        i = 0
        while True:
            try:
                fp.read_into(&orth, 1, sizeof(orth))
            except IOError:
                break
            lexeme = <LexemeC*>self.mem.alloc(sizeof(LexemeC), 1)
            # Copy data from the file into the lexeme
            fp.read_into(&lexeme.flags, 1, sizeof(lexeme.flags))
            fp.read_into(&lexeme.id, 1, sizeof(lexeme.id))
            fp.read_into(&lexeme.length, 1, sizeof(lexeme.length))
            fp.read_into(&lexeme.orth, 1, sizeof(lexeme.orth))
            fp.read_into(&lexeme.lower, 1, sizeof(lexeme.lower))
            fp.read_into(&lexeme.norm, 1, sizeof(lexeme.norm))
            fp.read_into(&lexeme.shape, 1, sizeof(lexeme.shape))
            fp.read_into(&lexeme.prefix, 1, sizeof(lexeme.prefix))
            fp.read_into(&lexeme.suffix, 1, sizeof(lexeme.suffix))
            fp.read_into(&lexeme.cluster, 1, sizeof(lexeme.cluster))
            fp.read_into(&lexeme.prob, 1, sizeof(lexeme.prob))
            fp.read_into(&lexeme.sentiment, 1, sizeof(lexeme.sentiment))
            fp.read_into(&lexeme.l2_norm, 1, sizeof(lexeme.l2_norm))

            lexeme.repvec = EMPTY_VEC
            py_str = self.strings[lexeme.orth]
            key = hash_string(py_str)
            self._by_hash.set(key, lexeme)
            self._by_orth.set(lexeme.orth, lexeme)
            self.length += 1
            i += 1
        fp.close()

    def load_vectors(self, file_):
        cdef LexemeC* lexeme
        cdef attr_t orth
        cdef int32_t vec_len = -1
        for line_num, line in enumerate(file_):
            pieces = line.split()
            word_str = pieces.pop(0)
            if vec_len == -1:
                vec_len = len(pieces)
            elif vec_len != len(pieces):
                raise VectorReadError.mismatched_sizes(file_, line_num,
                                                        vec_len, len(pieces))
            orth = self.strings[word_str]
            lexeme = <LexemeC*><void*>self.get_by_orth(self.mem, orth)
            lexeme.repvec = <float*>self.mem.alloc(self.vectors_length, sizeof(float))

            for i, val_str in enumerate(pieces):
                lexeme.repvec[i] = float(val_str)
        return vec_len

    def load_vectors_from_bin_loc(self, loc):
        cdef CFile file_ = CFile(loc, b'rb')
        cdef int32_t word_len
        cdef int32_t vec_len = 0
        cdef int32_t prev_vec_len = 0
        cdef float* vec
        cdef Address mem
        cdef attr_t string_id
        cdef bytes py_word
        cdef vector[float*] vectors
        cdef int line_num = 0
        cdef Pool tmp_mem = Pool()
        while True:
            try:
                file_.read_into(&word_len, sizeof(word_len), 1)
            except IOError:
                break
            file_.read_into(&vec_len, sizeof(vec_len), 1)
            if prev_vec_len != 0 and vec_len != prev_vec_len:
                raise VectorReadError.mismatched_sizes(loc, line_num,
                                                       vec_len, prev_vec_len)
            if 0 >= vec_len >= MAX_VEC_SIZE:
                raise VectorReadError.bad_size(loc, vec_len)

            chars = <char*>file_.alloc_read(tmp_mem, word_len, sizeof(char))
            vec = <float*>file_.alloc_read(self.mem, vec_len, sizeof(float))

            string_id = self.strings[chars[:word_len]]
            while string_id >= vectors.size():
                vectors.push_back(EMPTY_VEC)
            assert vec != NULL
            vectors[string_id] = vec
            line_num += 1
        cdef LexemeC* lex
        cdef size_t lex_addr
        cdef int i
        for orth, lex_addr in self._by_orth.items():
            lex = <LexemeC*>lex_addr
            if lex.lower < vectors.size():
                lex.repvec = vectors[lex.lower]
                for i in range(vec_len):
                    lex.l2_norm += (lex.repvec[i] * lex.repvec[i])
                lex.l2_norm = math.sqrt(lex.l2_norm)
            else:
                lex.repvec = EMPTY_VEC
        return vec_len


def unpickle_vocab(strings_loc, lex_loc, vec_loc, morphology, get_lex_attr,
                   serializer_freqs, data_dir):
    cdef Vocab vocab = Vocab()

    vocab.get_lex_attr = get_lex_attr
    vocab.morphology = morphology
    vocab.strings = morphology.strings
    vocab.data_dir = data_dir
    vocab.serializer_freqs = serializer_freqs

    vocab.load_lexemes(strings_loc, lex_loc)
    if vec_loc is not None:
        vocab.load_vectors_from_bin_loc(vec_loc)
    return vocab
 

copy_reg.constructor(unpickle_vocab)


def write_binary_vectors(in_loc, out_loc):
    cdef CFile out_file = CFile(out_loc, 'wb')
    cdef Address mem
    cdef int32_t word_len
    cdef int32_t vec_len
    cdef char* chars
    with bz2.BZ2File(in_loc, 'r') as file_:
        for line in file_:
            pieces = line.split()
            word = pieces.pop(0)
            mem = Address(len(pieces), sizeof(float))
            vec = <float*>mem.ptr
            for i, val_str in enumerate(pieces):
                vec[i] = float(val_str)

            word_len = len(word)
            vec_len = len(pieces)

            out_file.write_from(&word_len, 1, sizeof(word_len))
            out_file.write_from(&vec_len, 1, sizeof(vec_len))

            chars = <char*>word
            out_file.write_from(chars, len(word), sizeof(char))
            out_file.write_from(vec, vec_len, sizeof(float))


class LookupError(Exception):
    @classmethod
    def mismatched_strings(cls, id_, id_string, original_string):
        return cls(
            "Error fetching a Lexeme from the Vocab. When looking up a string, "
            "the lexeme returned had an orth ID that did not match the query string. "
            "This means that the cached lexeme structs are mismatched to the "
            "string encoding table. The mismatched:\n"
            "Query string: {query}\n"
            "Orth cached: {orth_str}\n"
            "ID of orth: {orth_id}".format(
                query=original_string, orth_str=id_string, orth_id=id_)
        )


class VectorReadError(Exception):
    @classmethod
    def mismatched_sizes(cls, loc, line_num, prev_size, curr_size):
        return cls(
            "Error reading word vectors from %s on line %d.\n"
            "All vectors must be the same size.\n"
            "Prev size: %d\n"
            "Curr size: %d" % (loc, line_num, prev_size, curr_size))

    @classmethod
    def bad_size(cls, loc, size):
        return cls(
            "Error reading word vectors from %s.\n"
            "Vector size: %d\n"
            "Max size: %d\n"
            "Min size: 1\n" % (loc, size, MAX_VEC_SIZE))
