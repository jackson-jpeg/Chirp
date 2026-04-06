#ifndef OPUS_CTL_SHIM_H
#define OPUS_CTL_SHIM_H

#include <stdint.h>

/// Opaque encoder handle (wraps OpusEncoder*).
typedef void *ChirpOpusEncoder;

/// Create an Opus encoder. Returns NULL on failure.
/// @param sampleRate Sample rate (8000, 12000, 16000, 24000, 48000)
/// @param channels Number of channels (1 or 2)
/// @param application 2048=VOIP, 2049=audio, 2051=low-delay
ChirpOpusEncoder chirp_opus_encoder_create(int32_t sampleRate, int32_t channels, int32_t application);

/// Destroy an Opus encoder.
void chirp_opus_encoder_destroy(ChirpOpusEncoder encoder);

/// Encode Int16 PCM to Opus. Returns encoded byte count, or negative error.
int32_t chirp_opus_encode(ChirpOpusEncoder encoder,
                          const int16_t *pcm,
                          int32_t frameSize,
                          uint8_t *output,
                          int32_t maxOutputBytes);

/// Set encoder bitrate in bits/second. Returns 0 on success.
int32_t chirp_opus_set_bitrate(ChirpOpusEncoder encoder, int32_t bitrate);

/// Get current encoder bitrate. Returns bitrate or negative error.
int32_t chirp_opus_get_bitrate(ChirpOpusEncoder encoder);

/// Enable or disable in-band Forward Error Correction (FEC). Returns 0 on success.
int32_t chirp_opus_set_inband_fec(ChirpOpusEncoder encoder, int32_t enabled);

/// Set expected packet loss percentage (0-100). Helps FEC decide redundancy level. Returns 0 on success.
int32_t chirp_opus_set_packet_loss_perc(ChirpOpusEncoder encoder, int32_t percentage);

#endif /* OPUS_CTL_SHIM_H */
