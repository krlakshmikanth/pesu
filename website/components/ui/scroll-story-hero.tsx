'use client';

import { FormEvent, useEffect, useRef, useState } from 'react';
import { PesuBrand } from './pesu-brand';

type JoinState = 'idle' | 'loading' | 'success' | 'existing' | 'error';

export function WaitlistForm({ id, compact = false }: { id: string; compact?: boolean }) {
  const [state, setState] = useState<JoinState>('idle');

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const data = new FormData(form);
    setState('loading');

    try {
      const response = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email: data.get('email'), company: data.get('company') }),
      });
      const result = (await response.json()) as { alreadyJoined?: boolean; error?: string };
      if (!response.ok) throw new Error(result.error ?? 'Could not join the waitlist.');
      setState(result.alreadyJoined ? 'existing' : 'success');
      form.reset();
    } catch {
      setState('error');
    }
  }

  const message = state === 'success'
    ? 'You’re in. Pēsu will be free for life.'
    : state === 'existing'
      ? 'You’re already on the list—we remember.'
      : state === 'error'
        ? 'Something went wrong. Please try again.'
        : 'No card. No spam. Just your invitation.';

  return (
    <div className={compact ? 'form-wrap compact' : 'form-wrap'}>
      <form className="waitlist-form" onSubmit={submit}>
        <label className="sr-only" htmlFor={`${id}-email`}>Email address</label>
        <input id={`${id}-email`} name="email" type="email" placeholder="you@company.com" autoComplete="email" required />
        <input className="honeypot" name="company" tabIndex={-1} autoComplete="off" aria-hidden="true" />
        <button type="submit" disabled={state === 'loading'}>
          {state === 'loading' ? 'Saving your place…' : 'Join the waitlist'}
          <span aria-hidden="true">↗</span>
        </button>
      </form>
      <p className={`form-message ${state}`} role="status" aria-live="polite">{message}</p>
    </div>
  );
}

const clamp = (value: number, min = 0, max = 1) => Math.min(max, Math.max(min, value));
const reveal = (progress: number, start: number, end: number) => clamp((progress - start) / (end - start));

export function ScrollStoryHero() {
  const shellRef = useRef<HTMLElement>(null);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    const shell = shellRef.current;
    if (!shell) return;
    const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reducedMotion) {
      setProgress(1);
      return;
    }

    let frame = 0;
    const update = () => {
      frame = 0;
      const rect = shell.getBoundingClientRect();
      const distance = Math.max(1, rect.height - window.innerHeight);
      const next = clamp(-rect.top / distance);
      setProgress((previous) => Math.abs(previous - next) > 0.001 ? next : previous);
    };
    const queue = () => {
      if (!frame) frame = requestAnimationFrame(update);
    };
    update();
    window.addEventListener('scroll', queue, { passive: true });
    window.addEventListener('resize', queue);
    return () => {
      window.removeEventListener('scroll', queue);
      window.removeEventListener('resize', queue);
      if (frame) cancelAnimationFrame(frame);
    };
  }, []);

  const introOut = 1 - reveal(progress, 0.15, 0.27);
  const lostIn = reveal(progress, 0.16, 0.28) * (1 - reveal(progress, 0.33, 0.43));
  const transcriptIn = reveal(progress, 0.34, 0.48) * (1 - reveal(progress, 0.58, 0.69));
  const cardsIn = reveal(progress, 0.56, 0.69) * (1 - reveal(progress, 0.78, 0.88));
  const privacyIn = reveal(progress, 0.75, 0.84) * (1 - reveal(progress, 0.89, 0.93));
  const finalIn = reveal(progress, 0.965, 0.995);

  return (
    <section ref={shellRef} className="story-shell" aria-label="The Pēsu story">
      <div className="story-hero" style={{ '--story': progress } as React.CSSProperties}>
        <nav className="hero-nav" aria-label="Primary navigation">
          <a className="brand" href="#top" aria-label="Pēsu home">
            <PesuBrand />
          </a>
        </nav>

        <div className="story-progress" aria-hidden="true"><i style={{ transform: `scaleX(${progress})` }} /></div>

        <div className="story-beat intro-beat" style={{ opacity: introOut }}>
          <h1 id="top">Every meeting starts with a voice.</h1>
        </div>

        <div className="story-beat lost-beat" style={{ opacity: lostIn, transform: `translateY(${(1 - lostIn) * 18}px)` }}>
          <h2>Then the meeting ends.</h2>
        </div>

        <div className="transcript-sheet" style={{ opacity: transcriptIn, transform: `translate(-50%, ${26 - transcriptIn * 26}px) scale(${.96 + transcriptIn * .04})` }}>
          <div className="sheet-top"><span>Live transcript</span><i>On device</i></div>
          <p><b>00:18</b> Let’s ship the smaller version first.</p>
          <p><b>00:27</b> Friday works for the team.</p>
          <p><b>00:34</b> Lak will speak to everyone tomorrow.</p>
        </div>
        <div className="result-cards" style={{ opacity: cardsIn, transform: `translate(-50%, ${24 - cardsIn * 24}px)` }}>
          <article><small>01 · BRIEF</small><h3>A focused version will ship first.</h3><p>The team aligned on a smaller initial release.</p></article>
          <article><small>02 · DECISION</small><h3>Ship on Friday.</h3><p><i /> Supported by the conversation</p></article>
          <article><small>03 · ACTION</small><h3>Speak to the team.</h3><p>Owner · Lak&nbsp;&nbsp; Due · Tomorrow</p></article>
        </div>

        <div className="mac-boundary" style={{ opacity: privacyIn, transform: `translate(-50%, -50%) scale(${1.05 - privacyIn * .05})` }}>
          <div className="mac-camera" />
          <strong>Your meeting never leaves your Mac.</strong>
          <div className="mac-foot" />
        </div>

        <div className="hero-copy final-beat" style={{ opacity: finalIn, transform: `translateY(${24 - finalIn * 24}px)`, pointerEvents: finalIn > .85 ? 'auto' : 'none' }}>
          <div className="final-brand"><PesuBrand large /></div>
          <WaitlistForm id="hero" />
          <p className="founder-note"><span aria-hidden="true">✦</span> Waitlist members get the core Pēsu app free for life.</p>
        </div>

        <div className="scroll-cue" aria-hidden="true" style={{ opacity: 1 - reveal(progress, .02, .12) }}>
          <span>Scroll to hear the story</span><i />
        </div>
      </div>
    </section>
  );
}
