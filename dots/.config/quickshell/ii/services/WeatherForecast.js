function degrees(celsius, useUSCS) {
    return Math.round(useUSCS ? celsius * 9 / 5 + 32 : celsius) + "°";
}

function chance(percent) {
    return typeof percent === "number" ? Math.round(percent) + "%" : "-";
}

// Compare the provider's local ISO times, so a pinned city's timezone does
// not get confused with the desktop's timezone when choosing upcoming hours.
function upcoming(reply, useUSCS) {
    const hourly = reply?.hourly;
    const now = reply?.current?.time;
    if (!hourly?.time || !now) return [];
    const result = [];
    for (let i = 0; i < hourly.time.length && result.length < 4; i++) {
        const celsius = hourly.temperature_2m?.[i];
        const code = hourly.weather_code?.[i];
        if (hourly.time[i] <= now || typeof celsius !== "number" || typeof code !== "number") continue;
        result.push({
            time: hourly.time[i].split("T")[1].slice(0, 5),
            temperature: degrees(celsius, useUSCS),
            code,
            isDay: hourly.is_day?.[i] !== 0,
            rain: chance(hourly.precipitation_probability?.[i])
        });
    }
    return result;
}

// The four days after the provider's own today, read in its local dates for the same reason.
function nextDays(reply, useUSCS) {
    const daily = reply?.daily;
    const today = reply?.current?.time?.split("T")[0];
    if (!daily?.time || !today) return [];
    const result = [];
    for (let i = 0; i < daily.time.length && result.length < 4; i++) {
        const high = daily.temperature_2m_max?.[i];
        const low = daily.temperature_2m_min?.[i];
        const code = daily.weather_code?.[i];
        if (daily.time[i] <= today || typeof high !== "number" || typeof low !== "number" || typeof code !== "number") continue;
        result.push({
            date: daily.time[i],
            high: degrees(high, useUSCS),
            low: degrees(low, useUSCS),
            code,
            rain: chance(daily.precipitation_probability_max?.[i])
        });
    }
    return result;
}

function condition(code) {
    if (code === 0) return "Clear sky";
    if (code === 1) return "Mostly clear";
    if (code === 2) return "Partly cloudy";
    if (code === 3) return "Overcast";
    if ([45, 48].includes(code)) return "Fog";
    if ([51, 53, 55].includes(code)) return "Drizzle";
    if ([56, 57, 66, 67].includes(code)) return "Freezing rain";
    if ([61, 63, 65].includes(code)) return "Rain";
    if ([71, 73, 75, 77].includes(code)) return "Snow";
    if ([80, 81, 82].includes(code)) return "Rain showers";
    if ([85, 86].includes(code)) return "Snow showers";
    if ([95, 96, 99].includes(code)) return "Thunderstorms";
    return "Weather unavailable";
}
