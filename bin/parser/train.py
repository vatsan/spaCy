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
from spacy.syntax.conll import read_docparse_file
from spacy.syntax.conll import GoldParse


def train(Language, train_loc, model_dir, n_iter=15, feat_set=u'basic', seed=0,
          gold_preproc=False, force_gold=False, n_sents=0):
    print "Setup model dir"
    dep_model_dir = path.join(model_dir, 'deps')
    pos_model_dir = path.join(model_dir, 'pos')
    ner_model_dir = path.join(model_dir, 'ner')
    if path.exists(dep_model_dir):
        shutil.rmtree(dep_model_dir)
    if path.exists(pos_model_dir):
        shutil.rmtree(pos_model_dir)
    if path.exists(ner_model_dir):
        shutil.rmtree(ner_model_dir)
    os.mkdir(dep_model_dir)
    os.mkdir(pos_model_dir)
    os.mkdir(ner_model_dir)

    setup_model_dir(sorted(POS_TAGS.keys()), POS_TAGS, POS_TEMPLATES, pos_model_dir)

    gold_tuples = read_docparse_file(train_loc)

    Config.write(dep_model_dir, 'config', features=feat_set, seed=seed,
                 labels=Language.ParserTransitionSystem.get_labels(gold_tuples))
    Config.write(ner_model_dir, 'config', features=feat_set, seed=seed,
                 labels=Language.EntityTransitionSystem.get_labels(gold_tuples))

    nlp = Language()
    
    for itn in range(n_iter):
        dep_corr = 0
        pos_corr = 0
        n_tokens = 0
        for raw_text, segmented_text, annot_tuples in gold_tuples:
            if gold_preproc:
                sents = [nlp.tokenizer.tokens_from_list(s) for s in segmented_text]
            else:
                sents = [nlp.tokenizer(raw_text)]
            for tokens in sents:

                gold = GoldParse(tokens, annot_tuples, nlp.tags,
                                 nlp.parser.moves.label_ids,
                                 nlp.entity.moves.label_ids)

                nlp.tagger(tokens)
                dep_corr += nlp.parser.train(tokens, gold, force_gold=force_gold)
                pos_corr += nlp.tagger.train(tokens, gold.tags_)
                n_tokens += len(tokens)
        acc = float(dep_corr) / n_tokens
        pos_acc = float(pos_corr) / n_tokens
        print '%d: ' % itn, '%.3f' % acc, '%.3f' % pos_acc
        random.shuffle(gold_tuples)
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
    gold_tuples = read_docparse_file(train_loc)
    for raw_text, segmented_text, annot_tuples in gold_tuples:
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
            if gold_sent.labels[i] != 'P':
                n_corr += gold_sent.is_correct(i, token.head.i)
                total += 1
    print loss, skipped, (loss+skipped + total)
    print pos_corr / n_tokens
    return float(n_corr) / (total + loss)



@plac.annotations(
    train_loc=("Training file location",),
    dev_loc=("Dev. file location",),
    model_dir=("Location of output model directory",),
    n_sents=("Number of training sentences", "option", "n", int)
)
def main(train_loc, dev_loc, model_dir, n_sents=0):
    train(English, train_loc, model_dir,
          gold_preproc=False, force_gold=False, n_sents=n_sents)
    print evaluate(English, dev_loc, model_dir, gold_preproc=False)
    

if __name__ == '__main__':
    plac.call(main)
