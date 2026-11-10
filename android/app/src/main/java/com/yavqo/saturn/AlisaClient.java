package com.yavqo.saturn;

import android.os.Handler;
import android.os.Looper;
import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;

/** Alisa — Saturn's assistant on Android. Talks to the same OpenAI-compatible gateway the desktop app uses. */
final class AlisaClient {
    static final String BASE_URL = BuildConfig.APINEX_BASE_URL;
    static final String MODEL = BuildConfig.APINEX_MODEL;

    interface Reply { void onReply(String text, String error); }

    private static final String PERSONA =
        "You are Alisa, a precise and friendly AI assistant by Yavqo. You are powered by Yavqo's Sunlight.\n"
      + "Answer directly. Ask a clarifying question when a request is ambiguous. Format longer answers so they are quick to scan: short paragraphs, bullet points, and bold key terms.\n"
      + "Never name or discuss any other AI model or company as the source of your abilities. If asked what model you run on, say you are Alisa, powered by Yavqo's Sunlight, and that you cannot go into more detail. You are an AI: never claim to be human.\n"
      + "You are integrated into the Saturn browser. Keep responses clear, helpful, and formatted in markdown.";

    static void ask(String question, String pageContext, Reply reply) {
        new Thread(() -> {
            String answer = null, error = null;
            try {
                JSONArray messages = new JSONArray();
                String system = pageContext == null || pageContext.isEmpty()
                    ? PERSONA
                    : PERSONA + "\n\nBrowser context (page you are looking at):\n" + pageContext;
                messages.put(new JSONObject().put("role", "system").put("content", system));
                messages.put(new JSONObject().put("role", "user").put("content", question));

                JSONObject body = new JSONObject();
                body.put("model", MODEL);
                body.put("messages", messages);
                body.put("temperature", 0.7);
                body.put("max_tokens", 2500);

                URL url = new URL(BASE_URL + "/chat/completions");
                HttpURLConnection conn = (HttpURLConnection) url.openConnection();
                conn.setRequestMethod("POST");
                conn.setConnectTimeout(20000);
                conn.setReadTimeout(60000);
                conn.setDoOutput(true);
                conn.setRequestProperty("Content-Type", "application/json");
                conn.setRequestProperty("Authorization", "Bearer " + BuildConfig.APINEX_API_KEY);

                try (OutputStream out = conn.getOutputStream()) {
                    out.write(body.toString().getBytes(StandardCharsets.UTF_8));
                }

                int code = conn.getResponseCode();
                InputStream stream = code >= 200 && code < 300 ? conn.getInputStream() : conn.getErrorStream();
                String raw = readAll(stream);
                if (code < 200 || code >= 300) {
                    error = "Alisa could not be reached (" + code + ").";
                    try {
                        JSONObject err = new JSONObject(raw);
                        if (err.has("error")) error = err.getJSONObject("error").optString("message", error);
                    } catch (JSONException ignored) { }
                } else {
                    JSONObject root = new JSONObject(raw);
                    JSONArray choices = root.optJSONArray("choices");
                    if (choices != null && choices.length() > 0) {
                        JSONObject message = choices.getJSONObject(0).optJSONObject("message");
                        if (message != null) answer = message.optString("content", "");
                    }
                    if (answer == null || answer.isEmpty()) error = "Alisa returned no reply.";
                }
            } catch (Exception e) {
                error = e.getMessage() != null ? e.getMessage() : "Network error.";
            }
            final String a = answer, b = error;
            new Handler(Looper.getMainLooper()).post(() -> reply.onReply(a, b));
        }).start();
    }

    private static String readAll(InputStream stream) throws IOException {
        if (stream == null) return "";
        StringBuilder out = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) out.append(line).append('\n');
        }
        return out.toString();
    }
}
