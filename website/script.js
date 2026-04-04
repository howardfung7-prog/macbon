// ========================================
// MacBon Landing Page — Script
// ========================================

// ── Hero MacBook tap animation ──

(function () {
    const hand = document.getElementById('demoHand');
    const toast = document.getElementById('macToast');
    const toastIcon = document.getElementById('toastIcon');
    const toastText = document.getElementById('toastText');
    const zoneLeft = document.getElementById('tapZoneLeft');
    const zoneRight = document.getElementById('tapZoneRight');

    if (!hand || !toast) return;

    const actions = [
        { emoji: '\u25B6\uFE0F', label: 'Play / Pause', side: 'left' },
        { emoji: '\uD83D\uDCF7', label: 'Screenshot!', side: 'right' },
        { emoji: '\uD83C\uDF19', label: 'Dark Mode', side: 'left' },
        { emoji: '\uD83D\uDD12', label: 'Lock Screen', side: 'right' },
        { emoji: '\uD83D\uDCAA', label: 'You got this!', side: 'left' },
        { emoji: '\uD83D\uDD07', label: 'Mute', side: 'right' },
        { emoji: '\u23F0',       label: '3:42 PM, 87%', side: 'left' },
        { emoji: '\uD83E\uDD86', label: 'Quack!', side: 'right' },
    ];

    const bubbles = [];
    for (let i = 1; i <= 8; i++) {
        bubbles.push(document.getElementById('bubble' + i));
    }

    let step = 0;
    let animating = false;

    function runTap() {
        if (animating) return;
        animating = true;

        const action = actions[step % actions.length];
        const isLeft = action.side === 'left';
        const bubbleEl = bubbles[step % bubbles.length];

        // Position hand over tap zone
        // Left zone: ~18% from left, Right zone: ~18% from right
        if (isLeft) {
            hand.style.left = '15%';
            hand.style.right = 'auto';
        } else {
            hand.style.right = '15%';
            hand.style.left = 'auto';
        }

        // Phase 1: Hand hovers above (0ms)
        hand.style.transition = 'none';
        hand.style.bottom = '110px';
        hand.style.opacity = '1';

        // Force reflow
        hand.offsetHeight;

        // Phase 2: Hand moves down to tap (200ms)
        hand.style.transition = 'bottom 0.2s cubic-bezier(.4,0,.2,1)';
        hand.style.bottom = '55px';

        setTimeout(function () {
            // Phase 3: Impact — show ripple, toast, bubble
            var zone = isLeft ? zoneLeft : zoneRight;
            if (zone) {
                zone.classList.add('tapped');
                var ripples = zone.querySelectorAll('.zone-ripple');
                ripples.forEach(function (r) {
                    r.classList.remove('active');
                    r.offsetHeight;
                    r.classList.add('active');
                });
            }

            // Show toast in screen
            toastIcon.textContent = action.emoji;
            toastText.textContent = action.label;
            toast.classList.add('show');

            // Show bubble
            if (bubbleEl) {
                bubbleEl.querySelector('.bubble-emoji').textContent = action.emoji;
                bubbleEl.querySelector('.bubble-label').textContent = action.label;
                bubbleEl.classList.remove('pop');
                bubbleEl.offsetHeight;
                bubbleEl.classList.add('pop');
            }

            // Phase 4: Hand bounces back up (150ms)
            setTimeout(function () {
                hand.style.transition = 'bottom 0.15s cubic-bezier(.0,.5,.5,1)';
        hand.style.bottom = '90px';
            }, 80);

            // Phase 5: Hand lifts away
            setTimeout(function () {
                hand.style.transition = 'bottom 0.3s ease-in, opacity 0.3s ease-in';
                hand.style.bottom = '130px';
                hand.style.opacity = '0.3';
            }, 400);

            // Clean up after full cycle
            setTimeout(function () {
                toast.classList.remove('show');
                if (zone) zone.classList.remove('tapped');
            }, 1200);

            setTimeout(function () {
                animating = false;
                step++;
            }, 1600);

        }, 220);
    }

    // Start the loop
    setTimeout(function () {
        runTap();
        setInterval(runTap, 2400);
    }, 800);
})();


// ── Scroll-triggered fade-up animations ──

var observer = new IntersectionObserver(
    function (entries) {
        entries.forEach(function (entry) {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
            }
        });
    },
    { threshold: 0.1, rootMargin: '0px 0px -30px 0px' }
);

document.querySelectorAll('.fade-up').forEach(function (el) { observer.observe(el); });

// Auto-add fade-up to key elements
document.querySelectorAll('.feature-card, .step, .proof-item, .preview-layout > *').forEach(function (el) {
    el.classList.add('fade-up');
    observer.observe(el);
});

// ── Animated number counters ──

var counterObserver = new IntersectionObserver(
    function (entries) {
        entries.forEach(function (entry) {
            if (!entry.isIntersecting) return;
            var el = entry.target;
            var target = el.dataset.count;
            if (!target || el.dataset.animated) return;
            el.dataset.animated = 'true';

            var end = parseInt(target, 10);
            var duration = 1000;
            var start = performance.now();

            function tick(now) {
                var elapsed = now - start;
                var progress = Math.min(elapsed / duration, 1);
                var eased = 1 - Math.pow(1 - progress, 3);
                el.textContent = Math.round(eased * end);
                if (progress < 1) requestAnimationFrame(tick);
            }
            requestAnimationFrame(tick);
        });
    },
    { threshold: 0.5 }
);

document.querySelectorAll('.proof-number[data-count]').forEach(function (el) {
    counterObserver.observe(el);
});

// ── Nav border on scroll ──

var nav = document.querySelector('.nav');
window.addEventListener('scroll', function () {
    if (window.scrollY > 50) {
        nav.style.borderBottomColor = 'rgba(0,0,0,0.1)';
    } else {
        nav.style.borderBottomColor = 'rgba(0,0,0,0.06)';
    }
}, { passive: true });

// ── Smooth anchor links ──

document.querySelectorAll('a[href^="#"]').forEach(function (link) {
    link.addEventListener('click', function (e) {
        var target = document.querySelector(link.getAttribute('href'));
        if (target) {
            e.preventDefault();
            target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
    });
});
