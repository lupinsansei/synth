#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <math.h>

/* These temporary mono buffers hold doubles. Both synth channels start with
   identical gain for sine/FM patches; independent stereo arrays are returned. */
static size_t buffer_size(pTHX_ UV frames) {
    if (frames > 0x07ffffff) croak("Native render buffer too large");
    return (size_t)frames * sizeof(double);
}

static SV *zero_buffer(pTHX_ size_t bytes) {
    SV *sv = newSVpvn("",0);
    SvGROW(sv,bytes+1);
    Zero(SvPVX(sv),bytes+1,char);
    SvCUR_set(sv,bytes);
    return sv;
}

static const double *samples_at(pTHX_ AV *buffers, SSize_t i, size_t expected) {
    SV **slot = av_fetch(buffers,i,0);
    STRLEN size;
    const char *data;
    if (!slot || !SvPOK(*slot)) croak("Missing native sample buffer");
    data = SvPVbyte(*slot,size);
    if (size != expected) croak("Native sample length mismatch");
    return (const double *)data;
}

static SV *stereo_output(pTHX_ const double *sum, UV frames, SSize_t count, int want_pcm, SV **samples) {
    AV *left, *right, *pair;
    SV *pcm;
    UV i;
    left=newAV(); right=newAV(); pair=newAV();
    av_push(pair,newRV_noinc((SV *)left));
    av_push(pair,newRV_noinc((SV *)right));
    *samples = sv_2mortal(newRV_noinc((SV *)pair));
    pcm = want_pcm ? sv_2mortal(zero_buffer(aTHX_ frames*4)) : &PL_sv_undef;
    if (frames) { av_extend(left,frames-1); av_extend(right,frames-1); }
    for (i=0; i<frames; ++i) {
        double value=sum[i]/count;
        av_push(left,newSVnv(value));
        av_push(right,newSVnv(value));
        if (want_pcm) {
            int s = value != value ? 0 : value>32767 ? 32767 : value < -32768 ? -32768 : (int)value;
            unsigned char *p=(unsigned char *)SvPVX(pcm)+4*i;
            p[0]=p[2]=(unsigned char)s;
            p[1]=p[3]=(unsigned char)((unsigned int)s >> 8);
        }
    }
    return pcm;
}

MODULE = Synth::Native    PACKAGE = Synth::Native
PROTOTYPES: DISABLE

void
_oscillator(AV *mods, UV frames, double frequency, double rate, double scale, double gain, double volume_decay, double freq_decay, UV delay)
    PPCODE:
        size_t bytes = buffer_size(aTHX_ frames);
        SSize_t count = av_len(mods)+1;
        UV i;
        SSize_t m;
        double phase = 0, increment;
        SV *buffer;
        double *out;
        if (rate <= 0 || delay > frames) croak("Invalid native oscillator parameters");
        increment = frequency/rate;
        buffer = sv_2mortal(zero_buffer(aTHX_ bytes));
        out = (double *)SvPVX(buffer);
        /* Accumulate modulation directly in the output buffer. Each modulator
           starts at its own time zero relative to the delayed carrier. */
        for (m=0; m<count; ++m) {
            const double *mod = samples_at(aTHX_ mods,m,bytes);
            for (i=0; i<frames-delay; ++i) out[delay+i] += mod[i];
        }
        for (i=delay; i<frames; ++i) {
            double modulation = out[i];
            out[i] = (sin(phase*6.28)*scale)*gain;
            phase += count ? (frequency+modulation/count)/rate : increment;
            if (gain<=0 || frequency<=0) {
                Zero(out+i+1,frames-i-1,double);
                break;
            }
            gain -= volume_decay;
            frequency -= freq_decay;
        }
        XPUSHs(buffer);

void
_noise(UV frames, double frequency, double rate, double scale, double gain, double volume_decay, double freq_decay, UV delay, int tuned)
    PPCODE:
        size_t bytes = buffer_size(aTHX_ frames);
        SV *buffer;
        double *out;
        double held = 0;
        U32 i;
        if (rate <= 0 || delay > frames) croak("Invalid native noise parameters");
        buffer = sv_2mortal(zero_buffer(aTHX_ bytes));
        out = (double *)SvPVX(buffer);
        /* Render before applying delay, as Perl does. Even cropped samples
           consume their random draws so subsequent voices keep the same sound. */
        for (i=0; i<frames && gain>0; ++i) {
            int draw = 1;
            if (tuned) {
                double period;
                /* Match Perl: retain the zero-filled remainder and RNG state
                   once tuned pitch reaches or crosses zero. */
                if (frequency <= 0) break;
                period = rate/frequency;
                if (period < 1) croak("Illegal modulus zero");
                draw = period >= frames ? i == 0 : i % (U32)period == 0;
            }
            if (draw) {
                if (!PL_srand_called) {
                    seedDrand01(Perl_seed(aTHX));
                    PL_srand_called = TRUE;
                }
                held = (int)(Drand01()*scale) - scale/2;
            }
            if (i < frames-delay) out[i+delay] = held*gain;
            if (volume_decay > 0) gain -= volume_decay;
            if (tuned && frequency > 0 && freq_decay > 0) frequency -= freq_decay;
        }
        XPUSHs(buffer);

void
_finish(AV *voices, UV frames, double attack_end, double decay_frames, int want_pcm, int packed_only=0)
    PPCODE:
        size_t bytes = buffer_size(aTHX_ frames);
        SSize_t count = av_len(voices)+1, v;
        double decay_end = attack_end+decay_frames;
        double decay_length = decay_end-attack_end;
        SV *mix;
        double *sum;
        UV i;
        if (!count) croak("Missing native voices");
        mix = sv_2mortal(zero_buffer(aTHX_ bytes));
        sum = (double *)SvPVX(mix);
        for (v=0; v<count; ++v) {
            const double *wave = samples_at(aTHX_ voices,v,bytes);
            for (i=0; i<frames; ++i) {
                double gain;
                if (i<attack_end) gain=i/attack_end;
                else if (i<decay_end) gain=1-(i-attack_end)/decay_length;
                else break;
                sum[i] += wave[i]*gain;
            }
        }
        if (packed_only) {
            for (i=0; i<frames; ++i) sum[i] /= count;
            XPUSHs(mix);
        } else {
            SV *samples;
            SV *pcm = stereo_output(aTHX_ sum, frames, count, want_pcm, &samples);
            EXTEND(SP,2);
            PUSHs(samples);
            PUSHs(pcm);
        }

void
_finish_chord(AV *tones, UV frames)
    PPCODE:
        size_t bytes = buffer_size(aTHX_ frames);
        SSize_t count = av_len(tones)+1, tone;
        SV *samples, *pcm;
        SV *mix = sv_2mortal(zero_buffer(aTHX_ bytes));
        double *sum = (double *)SvPVX(mix);
        UV i;
        if (!count) croak("Missing native chord tones");
        for (tone=0; tone<count; ++tone) {
            const double *wave = samples_at(aTHX_ tones,tone,bytes);
            for (i=0; i<frames; ++i) sum[i] += wave[i];
        }
        pcm = stereo_output(aTHX_ sum, frames, count, 1, &samples);
        EXTEND(SP,2);
        PUSHs(samples);
        PUSHs(pcm);
