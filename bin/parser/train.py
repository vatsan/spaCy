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


def train(Language, gold_sents, model_dir, n_iter=15, feat_set=u'basic', seed=0,
          gold_preproc=False, force_gold=False):
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
        for gold_sent in gold_sents:
            tokens = nlp.tokenizer(gold_sent.raw)
            gold_sent.align_to_tokens(tokens)
            nlp.tagger(tokens)
            heads_corr += nlp.parser.train(tokens, gold_sent, force_gold=force_gold)
            pos_corr += nlp.tagger.train(tokens, gold_parse.tags)
            n_tokens += len(tokens)
        acc = float(heads_corr) / n_tokens
        pos_acc = float(pos_corr) / n_tokens
        print '%d: ' % itn, '%.3f' % acc, '%.3f' % pos_acc
        random.shuffle(paragraphs)
    nlp.parser.model.end_training()
    nlp.tagger.model.end_training()
    return acc


def main(train_loc, dev_loc, model_dir):
    train(English, read_docparse_gold(train_loc), model_dir,
          gold_preproc=False, force_gold=False)
    print evaluate(English, read_docparse_gold(dev_loc), model_dir, gold_preproc=False)
    

if __name__ == '__main__':
    plac.call(main)
