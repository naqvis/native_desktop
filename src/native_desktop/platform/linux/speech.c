#include <stdint.h>
#include <stdlib.h>
#include <pthread.h>
#include <speech-dispatcher/libspeechd.h>

#define NATIVE_DESKTOP_MAX_SPEECH_VOICES 65536

typedef struct NativeDesktopSpeech {
    SPDConnection *connection;
    int client_id;
    int active_message_id;
    int finished_message_id;
    int speaking;
    struct NativeDesktopSpeech *next;
} NativeDesktopSpeech;

static pthread_mutex_t native_desktop_speech_mutex = PTHREAD_MUTEX_INITIALIZER;
static NativeDesktopSpeech *native_desktop_speech_connections = NULL;

void native_desktop_speech_close(NativeDesktopSpeech *speech);

static void native_desktop_speech_finished(size_t message_id, size_t client_id,
                                           SPDNotificationType state)
{
    NativeDesktopSpeech *speech;

    (void)state;
    pthread_mutex_lock(&native_desktop_speech_mutex);
    for (speech = native_desktop_speech_connections; speech != NULL; speech = speech->next) {
        if ((size_t)speech->client_id == client_id) {
            speech->finished_message_id = (int)message_id;
            if (speech->active_message_id == (int)message_id)
                speech->speaking = 0;
            break;
        }
    }
    pthread_mutex_unlock(&native_desktop_speech_mutex);
}

NativeDesktopSpeech *native_desktop_speech_open(void)
{
    NativeDesktopSpeech *speech = calloc(1, sizeof(*speech));
    if (speech == NULL)
        return NULL;

    speech->active_message_id = -1;
    speech->finished_message_id = -1;
    speech->connection = spd_open("native_desktop", NULL, NULL, SPD_MODE_THREADED);
    if (speech->connection == NULL) {
        free(speech);
        return NULL;
    }

    speech->client_id = spd_get_client_id(speech->connection);
    if (speech->client_id < 0) {
        spd_close(speech->connection);
        free(speech);
        return NULL;
    }

    speech->connection->callback_end = native_desktop_speech_finished;
    speech->connection->callback_cancel = native_desktop_speech_finished;

    pthread_mutex_lock(&native_desktop_speech_mutex);
    speech->next = native_desktop_speech_connections;
    native_desktop_speech_connections = speech;
    pthread_mutex_unlock(&native_desktop_speech_mutex);

    if (spd_set_notification_on(speech->connection, SPD_END) != 0 ||
        spd_set_notification_on(speech->connection, SPD_CANCEL) != 0) {
        native_desktop_speech_close(speech);
        return NULL;
    }

    return speech;
}

int native_desktop_speech_configure(NativeDesktopSpeech *speech,
                                    const char *voice_name,
                                    const char *language,
                                    int rate,
                                    int pitch,
                                    int volume)
{
    if (voice_name != NULL && spd_set_synthesis_voice(speech->connection, voice_name) != 0)
        return -1;
    if (language != NULL && spd_set_language(speech->connection, language) != 0)
        return -1;
    if (spd_set_voice_rate(speech->connection, rate) != 0)
        return -1;
    if (spd_set_voice_pitch(speech->connection, pitch) != 0)
        return -1;
    return spd_set_volume(speech->connection, volume);
}

int native_desktop_speech_say(NativeDesktopSpeech *speech, const char *text)
{
    int message_id = spd_say(speech->connection, SPD_TEXT, text);
    if (message_id < 0)
        return message_id;

    pthread_mutex_lock(&native_desktop_speech_mutex);
    speech->active_message_id = message_id;
    speech->speaking = speech->finished_message_id != message_id;
    pthread_mutex_unlock(&native_desktop_speech_mutex);
    return message_id;
}

int native_desktop_speech_stop(NativeDesktopSpeech *speech)
{
    int result = spd_stop(speech->connection);
    if (result == 0) {
        pthread_mutex_lock(&native_desktop_speech_mutex);
        speech->speaking = 0;
        pthread_mutex_unlock(&native_desktop_speech_mutex);
    }
    return result;
}

int native_desktop_speech_pause(NativeDesktopSpeech *speech)
{
    return spd_pause(speech->connection);
}

int native_desktop_speech_resume(NativeDesktopSpeech *speech)
{
    return spd_resume(speech->connection);
}

int native_desktop_speech_speaking(NativeDesktopSpeech *speech)
{
    int speaking;
    pthread_mutex_lock(&native_desktop_speech_mutex);
    speaking = speech->speaking;
    pthread_mutex_unlock(&native_desktop_speech_mutex);
    return speaking;
}

void native_desktop_speech_close(NativeDesktopSpeech *speech)
{
    NativeDesktopSpeech **current;

    if (speech == NULL)
        return;

    spd_set_notification_off(speech->connection, SPD_END);
    spd_set_notification_off(speech->connection, SPD_CANCEL);

    pthread_mutex_lock(&native_desktop_speech_mutex);
    current = &native_desktop_speech_connections;
    while (*current != NULL) {
        if (*current == speech) {
            *current = speech->next;
            break;
        }
        current = &(*current)->next;
    }
    pthread_mutex_unlock(&native_desktop_speech_mutex);

    spd_close(speech->connection);
    free(speech);
}

void *native_desktop_speech_list_voices(NativeDesktopSpeech *speech)
{
    return spd_list_synthesis_voices(speech->connection);
}

uint64_t native_desktop_speech_voice_count(void *opaque_voices)
{
    SPDVoice **voices = opaque_voices;
    uint64_t count = 0;

    if (voices == NULL)
        return 0;

    while (count < NATIVE_DESKTOP_MAX_SPEECH_VOICES && voices[count] != NULL)
        count++;

    return count == NATIVE_DESKTOP_MAX_SPEECH_VOICES ? UINT64_MAX : count;
}

const char *native_desktop_speech_voice_name(void *opaque_voices, uint64_t index)
{
    SPDVoice **voices = opaque_voices;
    return voices[index]->name;
}

const char *native_desktop_speech_voice_language(void *opaque_voices, uint64_t index)
{
    SPDVoice **voices = opaque_voices;
    return voices[index]->language;
}

const char *native_desktop_speech_voice_variant(void *opaque_voices, uint64_t index)
{
    SPDVoice **voices = opaque_voices;
    return voices[index]->variant;
}

void native_desktop_speech_free_voices(void *opaque_voices)
{
    free_spd_voices(opaque_voices);
}
