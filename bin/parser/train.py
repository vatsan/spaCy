#!/usr/bin/env python
from __future__ import division
from __future__ import unicode_literals

import os
from os import path
import shutil
import codecs
import random
import time
import gzip

import plac
import cProfile
import pstats

import spacy.util
from spacy.en import English
from spacy.en.pos import POS_TEMPLATES, POS_TAGS, setup_model_dir

from spacy.syntax.parser import GreedyParser
from spacy.syntax.parser import OracleError
from spacy.syntax.util import Config
from spacy.syntax.conll import GoldParse, is_punct_label


def train(Language, gold_sents, model_dir, n_iter=15, feat_set=u'basic', seed=0,
          gold_preproc=False, force_gold=False):
    print "Setup model dir"
    dep_model_dir = path.join(model_dir, 'deps')
    pos_model_dir = path.join(model_dir, 'pos')
    if path.exists(dep_model_dir):
        shutil.rmtree(dep_model_dir)
    if path.exists(pos_model_dir):
        shutil.rmtree(pos_model_dir)
    os.mkdir(dep_model_dir)
    os.mkdir(pos_model_dir)
    setup_model_dir(sorted(POS_TAGS.keys()), POS_TAGS, POS_TEMPLATES,
                    pos_model_dir)

    labels = Language.ParserTransitionSystem.get_labels(gold_sents)
    Config.write(dep_model_dir, 'config', features=feat_set, seed=seed,
                 labels=labels)
    nlp = Language()
    
    for itn in range(n_iter):
        heads_corr = 0
        pos_corr = 0
        n_tokens = 0
        n_all_tokens = 0
        for gold_sent in gold_sents:
            if gold_preproc:
                #print ' '.join(gold_sent.words)
                tokens = nlp.tokenizer.tokens_from_list(gold_sent.words)
                gold_sent.map_heads(nlp.parser.moves.label_ids)
            else:
                tokens = nlp.tokenizer(gold_sent.raw_text)
                gold_sent.align_to_tokens(tokens, nlp.parser.moves.label_ids)
            nlp.tagger(tokens)
            heads_corr += nlp.parser.train(tokens, gold_sent, force_gold=force_gold)
            pos_corr += nlp.tagger.train(tokens, gold_sent.tags)
            n_tokens += gold_sent.n_non_punct
            n_all_tokens += len(tokens)
        acc = float(heads_corr) / n_tokens
        pos_acc = float(pos_corr) / n_all_tokens
        print '%d: ' % itn, '%.3f' % acc, '%.3f' % pos_acc
        random.shuffle(gold_sents)
    nlp.parser.model.end_training()
    nlp.tagger.model.end_training()
    return acc


def evaluate(Language, gold_sents, model_dir, gold_preproc=False):
    global loss
    nlp = Language()
    uas_corr = 0
    las_corr = 0
    pos_corr = 0
    n_tokens = 0
    total = 0
    skipped = 0
    loss = 0
    for gold_sent in gold_sents:
        if gold_preproc:
            tokens = nlp.tokenizer.tokens_from_list(gold_sent.words)
            nlp.tagger(tokens)
            nlp.parser(tokens)
            gold_sent.map_heads(nlp.parser.moves.label_ids)
        else:
            tokens = nlp(gold_sent.raw_text)
            loss += gold_sent.align_to_tokens(tokens, nlp.parser.moves.label_ids)
        for i, token in enumerate(tokens):
            pos_corr += token.tag_ == gold_sent.tags[i]
            n_tokens += 1
            if gold_sent.heads[i] is None:
                skipped += 1
                continue
<<<<<<< HEAD
            #print i, token.orth_, token.head.i, gold_sent.py_heads[i], gold_sent.labels[i],
            #print gold_sent.is_correct(i, token.head.i)
            if gold_sent.labels[i] != 'P':
                n_corr += gold_sent.is_correct(i, token.head.i)
                total += 1
=======
            if is_punct_label(labels[i]):
                continue
            uas_corr += token.head.i == heads[i]
            las_corr += token.head.i == heads[i] and token.dep_ == labels[i]
            #print token.orth_, token.head.orth_, token.dep_, labels[i]
            total += 1
>>>>>>> master
    print loss, skipped, (loss+skipped + total)
    print pos_corr / n_tokens
    print float(las_corr) / (total + loss)
    return float(uas_corr) / (total + loss)


def read_gold(loc, n=0):
    sent_strs = open(loc).read().strip().split('\n\n')
    if n == 0:
        n = len(sent_strs)
    return [GoldParse.from_docparse(sent) for sent in sent_strs[:n]]


@plac.annotations(
    train_loc=("Training file location",),
    dev_loc=("Dev. file location",),
    model_dir=("Location of output model directory",),
    n_sents=("Number of training sentences", "option", "n", int)
)
def main(train_loc, dev_loc, model_dir, n_sents=0):
    #train(English, read_gold(train_loc, n=n_sents), model_dir,
    #      gold_preproc=False, force_gold=False)
    print evaluate(English, read_gold(dev_loc), model_dir, gold_preproc=False)
    

if __name__ == '__main__':
    plac.call(main)
