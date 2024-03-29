. ./path.sh
. ./cmd.sh
echo "preparing data"

do_delta=false
#recog_set="ES_L1_test DS_L1_test MS_L1_test"
#recog_set="DS_L2_F_test"
recog_set="DS_L2_debug"
#recog_set="L2_train"
#recog_set="L2_T_train"
#recog_set="L2_test"
nj=2
stage=0
if [ ${stage} -le 0 ]; then
    for rtask in ${recog_set}; do
        steps/make_fbank_pitch.sh --cmd "$train_cmd" --nj $nj data/$rtask exp/make_fbank/$rtask fbank_${rtask}
        feat_recog_dir=dump/${rtask}/delta${do_delta}
        mkdir -p ${feat_recog_dir}
        compute-cmvn-stats scp:data/$rtask/feats.scp data/$rtask/cmvn.ark
        utils/fix_data_dir.sh data/$rtask
        echo ${rtask}
        dump.sh --cmd "$train_cmd" --nj $nj --do_delta $do_delta \
        data/${rtask}/feats.scp data/${rtask}/cmvn.ark exp/dump_feats/$rtask ${feat_recog_dir}
        data2json.sh --feat dump/$rtask/deltafalse/feats.scp --nlsyms data/lang_1char/non_lang_syms.txt data/${rtask} data/lang_1char/L1L2_train_sp_units.txt > dump/$rtask/deltafalse/data.json
    done
fi

if [ ${stage} -le 1 ]; then
    echo "decoding"
    #some decoding paprameter
    nj=2
    backend=pytorch
    beam_size=40
    recog_model=model.acc.best
    penalty=0.0
    minlenratio=0.0
    maxlenratio=0.0
    ctc_weight=0.5
    #lm_weight=0.9
    #expdir=exp/train_lsm_pytorch_vggblstmp_e6_subsample1_2_2_1_1_unit320_proj320_d1_unit300_location_aconvc10_aconvf100_mtlalpha0.5_adadelta_sampprob0.0_bs10_mli800_mlo150_decoder-drop_0.0
    expdir=exp/train_pytorch_vggblstmp_e3_subsample1_2_2_1_1_unit1024_proj1024_d2_unit1024_location_aconvc10_aconvf100_mtlalpha0.5_adadelta_sampprob0.0_bs10_mli800_mlo150_decoder-drop_0.0_sigmoid_att
    dict=data/lang_1char/L1L2_train_sp_units.txt
    #lmexpdir=exp/train_rnnlm_layer_bs1024
    nlsyms=data/lang_1char/train.txt
    for rtask in ${recog_set}; do    
        decode_dir=decode_${rtask}_beam${beam_size}_e${recog_model}_p${penalty}_len${minlenratio}-${maxlenratio}_ctcw${ctc_weight}_L1
        #decode_dir=decode_${rtask}_beam${beam_size}_e${recog_model}_p${penalty}_len${minlenratio}-${maxlenratio}_ctcw${ctc_weight}_wordrnnlm${lm_weight}_multi
        # split data
        splitjson.py --parts ${nj} dump/${rtask}/delta${do_delta}/data.json
        ${decode_cmd} JOB=1:${nj} ${expdir}/${decode_dir}/log/decode.JOB.log \
            asr_recog.py \
            --batchsize 0 \
            --backend ${backend} \
            --recog-json dump/${rtask}/delta${do_delta}/split${nj}utt/data.JOB.json \
            --result-label ${expdir}/${decode_dir}/data.JOB.json \
            --model ${expdir}/results/${recog_model}  \
            --beam-size ${beam_size} \
            --penalty ${penalty} \
            --maxlenratio ${maxlenratio} \
            --minlenratio ${minlenratio} \
            --ctc-weight ${ctc_weight} \
            --nbest 5 \
            #--lm-weight ${lm_weight} \
            #--rnnlm ${lmexpdir}/rnnlm.model.best 
        wait
        score_sclite.sh --wer false --nlsyms ${nlsyms} ${expdir}/${decode_dir} ${dict}
    done
fi
