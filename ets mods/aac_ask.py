"""
C.A.S.I cog: /ask_aac — free-form ArcheAge Chronicles Q&A.

Works like /ask_div: the member's question goes to the Claude API with the
ArcheAge Chronicles knowledge pack as context, and the answer comes back as
a C.A.S.I embed.

Install on the VPS:
  1. Copy this file to   /opt/casi/cogs/aac_ask.py
  2. Copy the pack to    /opt/casi/data/knowledge/archeage_chronicles.md
  3. Add "cogs.aac_ask" to the COGS list in /opt/casi/bot.py
  4. sudo systemctl restart casi

Uses the same ANTHROPIC_API_KEY as /ask_div (systemd drop-in anthropic.conf).
Optional env vars:
  CASI_EMBLEM_URL  - Savage Rogues emblem (embed thumbnail)
  CASI_HOLO_URL    - C.A.S.I blue holographic image (embed author icon)
  AAC_KNOWLEDGE    - override path to the knowledge pack
  AAC_MODEL        - override the Claude model
"""

import os
import time
from pathlib import Path

import discord
from discord import app_commands
from discord.ext import commands
from anthropic import AsyncAnthropic

KNOWLEDGE_PATH = Path(os.getenv(
    "AAC_KNOWLEDGE", "/opt/casi/data/knowledge/archeage_chronicles.md"))
MODEL = os.getenv("AAC_MODEL", "claude-haiku-5-5")
EMBLEM_URL = os.getenv("CASI_EMBLEM_URL", "")
HOLO_URL = os.getenv("CASI_HOLO_URL", "")
COOLDOWN_SECONDS = 20
MAX_QUESTION = 500
EMBED_COLOUR = 0x2FA8FF  # C.A.S.I holo blue

SYSTEM_PROMPT = """You are C.A.S.I, the AI assistant of the Savage Rogues gaming Discord.
Answer members' questions about ArcheAge Chronicles (XLGAMES MMORPG, Early Access since 3 Nov 2026).
Rules:
- Use the knowledge pack below as your main source. If it doesn't cover the question,
  say so plainly and point to the most relevant Wikily link from the pack. Never invent
  numbers, drop rates, locations or skills.
- The game is in Early Access, so mention that details can change when it matters.
- Keep answers short and Discord-friendly: under 1,500 characters, simple bullets, no tables.
- Friendly, direct tone. You are openly an AI.

=== KNOWLEDGE PACK ===
{knowledge}
"""


class AACAsk(commands.Cog):
    def __init__(self, bot: commands.Bot):
        self.bot = bot
        self.client = AsyncAnthropic()  # reads ANTHROPIC_API_KEY
        self._last_use: dict[int, float] = {}
        self.knowledge = self._load_knowledge()

    def _load_knowledge(self) -> str:
        try:
            return KNOWLEDGE_PATH.read_text(encoding="utf-8")
        except OSError as e:
            print(f"[aac_ask] knowledge pack not found at {KNOWLEDGE_PATH}: {e}")
            return "(knowledge pack missing)"

    def _embed(self, title: str, text: str) -> discord.Embed:
        embed = discord.Embed(title=title, description=text[:4000], colour=EMBED_COLOUR)
        if HOLO_URL:
            embed.set_author(name="C.A.S.I", icon_url=HOLO_URL)
        else:
            embed.set_author(name="C.A.S.I")
        if EMBLEM_URL:
            embed.set_thumbnail(url=EMBLEM_URL)
        embed.set_footer(text="Savage Rogues • ArcheAge Chronicles • info via Wikily (Early Access, may change)")
        return embed

    @app_commands.command(name="ask_aac", description="Ask C.A.S.I anything about ArcheAge Chronicles")
    @app_commands.describe(question="Your ArcheAge Chronicles question")
    async def ask_aac(self, interaction: discord.Interaction, question: str):
        now = time.monotonic()
        last = self._last_use.get(interaction.user.id, 0)
        if now - last < COOLDOWN_SECONDS:
            wait = int(COOLDOWN_SECONDS - (now - last)) + 1
            await interaction.response.send_message(
                f"Give me {wait}s before the next question.", ephemeral=True)
            return
        self._last_use[interaction.user.id] = now

        question = question.strip()[:MAX_QUESTION]
        await interaction.response.defer(thinking=True)
        try:
            resp = await self.client.messages.create(
                model=MODEL,
                max_tokens=700,
                system=SYSTEM_PROMPT.format(knowledge=self.knowledge),
                messages=[{"role": "user", "content": question}],
            )
            answer = "".join(b.text for b in resp.content if b.type == "text").strip()
            if not answer:
                answer = "I couldn't come up with an answer to that one."
        except Exception as e:  # keep the bot alive whatever the API does
            print(f"[aac_ask] API error: {e!r}")
            await interaction.followup.send(
                embed=self._embed("ArcheAge Chronicles", "My link to the knowledge core failed. Try again in a minute."))
            return

        await interaction.followup.send(embed=self._embed(f"❓ {question[:240]}", answer))

    @app_commands.command(name="aac_reload", description="(Admin) Reload the ArcheAge Chronicles knowledge pack")
    @app_commands.default_permissions(administrator=True)
    async def aac_reload(self, interaction: discord.Interaction):
        self.knowledge = self._load_knowledge()
        await interaction.response.send_message(
            f"ArcheAge Chronicles pack reloaded ({len(self.knowledge):,} characters).", ephemeral=True)


async def setup(bot: commands.Bot):
    await bot.add_cog(AACAsk(bot))
