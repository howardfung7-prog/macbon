// Live stats polling — shared by all pages
// Fetches /functions/v1/stats every 30 seconds and updates the strip

(function () {
    const SUPABASE_URL = 'https://ikmjwquwrqxpkxwtgjkw.supabase.co';
    const REFRESH_MS = 30000;

    function fmtNum(n) {
        if (n === null || n === undefined) return '—';
        if (n >= 1_000_000_000) return (n / 1_000_000_000).toFixed(2) + 'B';
        if (n >= 1_000_000)     return (n / 1_000_000).toFixed(2) + 'M';
        if (n >= 10_000)        return (n / 1_000).toFixed(1) + 'K';
        return Math.round(n).toLocaleString();
    }

    function update(el, val, suffix) {
        if (!el) return;
        const newText = fmtNum(val) + (suffix || '');
        if (el.textContent !== newText && el.textContent !== '—') {
            // brief green pulse on change
            el.classList.add('pulse');
            setTimeout(() => el.classList.remove('pulse'), 800);
        }
        el.textContent = newText;
    }

    // ISO 3166-1 alpha-2 → emoji flag (regional indicator symbols)
    function flagEmoji(code) {
        if (!code || code.length !== 2) return '🌍';
        return code.toUpperCase().replace(/./g, c =>
            String.fromCodePoint(127397 + c.charCodeAt(0))
        );
    }

    // Country code → human name via browser Intl API
    const regionNames = (typeof Intl !== 'undefined' && Intl.DisplayNames)
        ? new Intl.DisplayNames(['en'], { type: 'region' })
        : null;
    function countryName(code) {
        try { return regionNames?.of(code) ?? code; }
        catch { return code; }
    }

    function renderLeaderboard(byCountry) {
        const lb = document.getElementById('geoLeaderboard');
        const countEl = document.getElementById('geoCountriesCount');
        const topFlagEl = document.getElementById('geoTopFlag');
        const topPctEl = document.getElementById('geoTopPct');
        if (!lb) return;

        const entries = Object.entries(byCountry || {})
            .sort((a, b) => b[1] - a[1])
            .slice(0, 10);

        const total = entries.reduce((s, [, c]) => s + c, 0);
        const maxCount = entries[0]?.[1] ?? 0;

        if (countEl) countEl.textContent = Object.keys(byCountry || {}).length || '—';

        if (entries.length === 0) {
            if (topFlagEl) topFlagEl.textContent = '🌍';
            if (topPctEl) topPctEl.textContent = '—';
            lb.innerHTML = '<div class="geo-empty">Waiting for the first miners to come online…</div>';
            return;
        }

        if (topFlagEl) topFlagEl.textContent = flagEmoji(entries[0][0]);
        if (topPctEl) topPctEl.textContent = ((entries[0][1] / total) * 100).toFixed(0) + '%';

        lb.innerHTML = entries.map(([code, count]) => {
            const pct = total ? (count / total) * 100 : 0;
            const widthPct = maxCount ? (count / maxCount) * 100 : 0;
            return `
                <div class="geo-row">
                    <span class="geo-flag">${flagEmoji(code)}</span>
                    <div class="geo-row-mid">
                        <div class="geo-row-top">
                            <span class="geo-name">${countryName(code)}</span>
                            <span class="geo-pct">${pct.toFixed(1)}%</span>
                        </div>
                        <div class="geo-bar"><div class="geo-bar-fill" style="width:${widthPct}%"></div></div>
                    </div>
                    <span class="geo-count">${count.toLocaleString()}</span>
                </div>
            `;
        }).join('');
    }

    async function fetchStats() {
        try {
            const res = await fetch(`${SUPABASE_URL}/functions/v1/stats`, {
                cache: 'no-store',
            });
            if (!res.ok) return;
            const data = await res.json();
            update(document.getElementById('statActiveDevices'), data.activeDevices);
            update(document.getElementById('statDistributed'),    data.totalDistributed, ' BON');
            update(document.getElementById('statLocked'),         data.totalLocked, ' BON');
            update(document.getElementById('statToday'),          data.todayRewards, ' BON');

            // Country leaderboard (only on pages that have it)
            renderLeaderboard(data.byCountry);

            // Optionally also drive the claim-page progress bar if present
            if (typeof window.updateProgress === 'function') {
                window.updateProgress(data.activeDevices ?? 0);
            }
        } catch (e) { /* silent */ }
    }

    // Kick off immediately, then poll
    fetchStats();
    setInterval(fetchStats, REFRESH_MS);
})();
