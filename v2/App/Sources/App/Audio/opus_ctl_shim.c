#include "opus_ctl_shim.h"

// Forward-declare libopus symbols. These are linked from the Copus SPM target.
// We avoid #include <opus.h> because the SPM module headers aren't on the
// app target's header search path.
typedef struct OpusEncoder OpusEncoder;
extern OpusEncoder *opus_encoder_create(int Fs, int channels, int application, int *error);
extern void opus_encoder_destroy(OpusEncoder *st);
extern int opus_encode(OpusEncoder *st, const int16_t *pcm, int frame_size,
                       unsigned char *data, int max_data_bytes);
extern int opus_encoder_ctl(OpusEncoder *st, int request, ...);

#define OPUS_SET_BITRATE_REQUEST 4002
#define OPUS_GET_BITRATE_REQUEST 4003
#define OPUS_SET_INBAND_FEC_REQUEST 4012
#define OPUS_SET_PACKET_LOSS_PERC_REQUEST 4014

ChirpOpusEncoder chirp_opus_encoder_create(int32_t sampleRate, int32_t channels, int32_t application) {
    int error = 0;
    OpusEncoder *enc = opus_encoder_create(sampleRate, channels, application, &error);
    if (error != 0 || enc == NULL) return NULL;
    return (ChirpOpusEncoder)enc;
}

void chirp_opus_encoder_destroy(ChirpOpusEncoder encoder) {
    if (encoder) opus_encoder_destroy((OpusEncoder *)encoder);
}

int32_t chirp_opus_encode(ChirpOpusEncoder encoder,
                          const int16_t *pcm,
                          int32_t frameSize,
                          uint8_t *output,
                          int32_t maxOutputBytes) {
    return opus_encode((OpusEncoder *)encoder, pcm, frameSize, output, maxOutputBytes);
}

int32_t chirp_opus_set_bitrate(ChirpOpusEncoder encoder, int32_t bitrate) {
    return opus_encoder_ctl((OpusEncoder *)encoder, OPUS_SET_BITRATE_REQUEST, (int)bitrate);
}

int32_t chirp_opus_get_bitrate(ChirpOpusEncoder encoder) {
    int bitrate = 0;
    int err = opus_encoder_ctl((OpusEncoder *)encoder, OPUS_GET_BITRATE_REQUEST, &bitrate);
    if (err < 0) return err;
    return (int32_t)bitrate;
}

int32_t chirp_opus_set_inband_fec(ChirpOpusEncoder encoder, int32_t enabled) {
    return opus_encoder_ctl((OpusEncoder *)encoder, OPUS_SET_INBAND_FEC_REQUEST, (int)enabled);
}

int32_t chirp_opus_set_packet_loss_perc(ChirpOpusEncoder encoder, int32_t percentage) {
    return opus_encoder_ctl((OpusEncoder *)encoder, OPUS_SET_PACKET_LOSS_PERC_REQUEST, (int)percentage);
}
