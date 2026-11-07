package errormonitor;

import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

final class Text {
    private static final ZoneId ZONE = ZoneId.systemDefault();
    private static final DateTimeFormatter CLOCK = DateTimeFormatter.ofPattern("HH:mm:ss.SSS").withZone(ZONE);
    private static final DateTimeFormatter CLOCK_SECONDS = DateTimeFormatter.ofPattern("HH:mm:ss").withZone(ZONE);
    private static final DateTimeFormatter DATE_TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss").withZone(ZONE);
    private static final DateTimeFormatter FOLDER = DateTimeFormatter.ofPattern("yyyy-MM-dd_HH-mm-ss").withZone(ZONE);

    private Text() {
    }

    static String clock(long millis) {
        return CLOCK.format(Instant.ofEpochMilli(millis));
    }

    static String clockSeconds(long millis) {
        return CLOCK_SECONDS.format(Instant.ofEpochMilli(millis));
    }

    static String dateTime(long millis) {
        return DATE_TIME.format(Instant.ofEpochMilli(millis));
    }

    static String folderName(long millis) {
        return FOLDER.format(Instant.ofEpochMilli(millis));
    }

    static String firstLine(String s) {
        if (s == null) {
            return "";
        }
        int end = s.indexOf('\n');
        String line = end < 0 ? s : s.substring(0, end);
        return line.endsWith("\r") ? line.substring(0, line.length() - 1) : line;
    }

    static String rest(String s) {
        if (s == null) {
            return "";
        }
        int end = s.indexOf('\n');
        return end < 0 ? "" : s.substring(end + 1);
    }

    static String clip(String s, int max) {
        if (s == null) {
            return "";
        }
        return s.length() <= max ? s : s.substring(0, max - 3) + "...";
    }

    static String oneLine(String s, int max) {
        return clip(s == null ? "" : s.replace('\t', ' ').replace('\r', ' ').replace('\n', ' ').trim(), max);
    }

    static String pad(String s, int width) {
        if (s.length() >= width) {
            return s;
        }
        StringBuilder b = new StringBuilder(width).append(s);
        while (b.length() < width) {
            b.append(' ');
        }
        return b.toString();
    }

    static String padLeft(String s, int width) {
        if (s.length() >= width) {
            return s;
        }
        StringBuilder b = new StringBuilder(width);
        for (int i = s.length(); i < width; i++) {
            b.append(' ');
        }
        return b.append(s).toString();
    }

    static String count(long n) {
        return String.format("%,d", n);
    }

    static String plural(long n, String one, String many) {
        return count(n) + " " + (n == 1 ? one : many);
    }

    // Numbers, object hashes (Foo@1a2b3c) and Lua addresses (0x1a2b) become '#', so messages that only
    // differ in those count as the same message.
    static String normalize(String s, int max) {
        int n = Math.min(s.length(), max);
        StringBuilder b = new StringBuilder(n);
        int i = 0;
        while (i < n) {
            char c = s.charAt(i);
            if (c == '@' && i + 1 < n && isHex(s.charAt(i + 1))) {
                b.append("@#");
                i++;
                while (i < n && isHex(s.charAt(i))) {
                    i++;
                }
                continue;
            }
            if (c == '0' && i + 2 < n && (s.charAt(i + 1) == 'x' || s.charAt(i + 1) == 'X') && isHex(s.charAt(i + 2))) {
                b.append('#');
                i += 2;
                while (i < n && isHex(s.charAt(i))) {
                    i++;
                }
                continue;
            }
            if (isDigit(c)) {
                b.append('#');
                i++;
                while (i < n && (isDigit(s.charAt(i)) || (s.charAt(i) == '.' && i + 1 < n && isDigit(s.charAt(i + 1))))) {
                    i++;
                }
                continue;
            }
            b.append(c);
            i++;
        }
        return b.toString();
    }

    private static boolean isDigit(char c) {
        return c >= '0' && c <= '9';
    }

    private static boolean isHex(char c) {
        return isDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }
}
