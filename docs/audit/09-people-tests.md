# 09. Two tests with people

The simulator proves the app works. These two show whether it lands. Both are run by Graham; Claude turns the answers
into findings in `backlog.csv` (prefix `UX-`).

## 1. First impression (5 seconds)

**Question it answers:** does the welcome screen say what Shoebox is, before anyone explains it?

**Who:** 3 to 5 people who have never seen Shoebox. Not the TestFlight testers.

**How:**
1. Open Shoebox's welcome screen (or show `light-welcome.png` from the `ci-screens` branch) full screen.
2. Say: "I'll show you a screen for five seconds. Then I'll ask you about it."
3. Show it for 5 seconds, then put the phone face down.
4. Ask the three questions below, in order. Write down their words exactly. Don't correct or explain.

**The questions:**
1. What do you think this app does?
2. Who do you think it's for?
3. What do you remember seeing?

**It passes when** most people say something close to "it brings things back to me", "it saves things and reminds
me", or "it's a place to keep things for later". It fails when people say "a shoe store", "a storage app", or can't say.

**Message to send someone remote** (they open the picture you attach, look for five seconds, then answer):

> Quick favor, 1 minute. Open the picture I'm sending, look at it for 5 seconds, then close it. Without looking again, tell me: 1) What do you think this app does? 2) Who's it for? 3) What do you remember seeing? There are no wrong answers, I'm testing the screen, not you.

## 2. Two weeks with Shoebox (diary)

**Question it answers:** does the promise hold over days? Did the right thing come back at the right time, and did the
daily stack feel calm or like a chore? No walk-through can show this.

**Who:** 2 or 3 of the TestFlight testers, using Shoebox for real things for 14 days.

**How:** send the kickoff message once, the day 3, 7 and 14 check-ins on those days. Each takes them under a minute.
Paste their replies to Claude.

**Kickoff (day 0):**

> Thanks for testing Shoebox. For the next two weeks, could you use it for real? Save anything you'd normally screenshot, email to yourself, or forget about: links, school emails, a thing to buy, a note. Then just open it when it tells you to. I'll text you three times with two quick questions each. That's all.

**Day 3:**

> Shoebox check-in (day 3): 1) Did anything come back to you that you were glad to see? What was it? 2) Was anything annoying or confusing?

**Day 7:**

> Shoebox check-in (day 7): 1) How many days this week did you open it? 2) Did anything come back at the wrong time, or not come back when you expected?

**Day 14:**

> Last Shoebox check-in (day 14): 1) On a scale of 1 to 10, how likely are you to keep using it? 2) If Shoebox disappeared tomorrow, what would you miss, if anything? 3) One thing you'd change?

**What to look for:**
- **Came back right:** examples of things returning at a useful moment (the core promise).
- **Came back wrong:** anything too early, too late or never. Each is a rules finding (Opus).
- **The daily habit:** 4 or more days a week by day 7 is healthy; 1 or 2 means the daily moment isn't working.
- **Day 14 score:** 8 to 10 is strong, 6 to 7 lukewarm, 5 or under a problem.
- **"What would you miss":** the honest answer to whether Shoebox matters. "Nothing" from more than one person is the
  most important finding of the whole audit.
