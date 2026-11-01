/*
 * Copyright 2012-2025 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.springframework.samples.petclinic;

import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.time.temporal.Temporal;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.DisabledInNativeImage;
import org.thymeleaf.expression.Numbers;
import org.thymeleaf.expression.Strings;
import org.thymeleaf.expression.Temporals;
import org.thymeleaf.spring6.expression.Fields;

import org.springframework.aot.hint.RuntimeHints;
import org.springframework.aot.hint.predicate.RuntimeHintsPredicates;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;
import org.springframework.util.StringUtils;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tests for {@link PetClinicRuntimeHints}.
 */
class PetClinicRuntimeHintsTests {

	/**
	 * A helper use: {@code #helper.method(} (call) or {@code #helper.property} (getter).
	 */
	private static final Pattern HELPER_USE = Pattern.compile("#(\\w+)\\.(\\w+)(\\s*\\()?");

	/**
	 * Thymeleaf expression utility objects ({@code #name}) and the classes behind them.
	 */
	private static final Map<String, String> HELPER_CLASSES = Map.ofEntries(
			Map.entry("aggregates", "org.thymeleaf.expression.Aggregates"),
			Map.entry("arrays", "org.thymeleaf.expression.Arrays"),
			Map.entry("bools", "org.thymeleaf.expression.Bools"),
			Map.entry("calendars", "org.thymeleaf.expression.Calendars"),
			Map.entry("conversions", "org.thymeleaf.expression.Conversions"),
			Map.entry("dates", "org.thymeleaf.expression.Dates"),
			Map.entry("execInfo", "org.thymeleaf.expression.ExecutionInfo"),
			Map.entry("ids", "org.thymeleaf.expression.Ids"), Map.entry("lists", "org.thymeleaf.expression.Lists"),
			Map.entry("maps", "org.thymeleaf.expression.Maps"),
			Map.entry("messages", "org.thymeleaf.expression.Messages"),
			Map.entry("numbers", "org.thymeleaf.expression.Numbers"),
			Map.entry("objects", "org.thymeleaf.expression.Objects"),
			Map.entry("sets", "org.thymeleaf.expression.Sets"),
			Map.entry("strings", "org.thymeleaf.expression.Strings"),
			Map.entry("temporals", "org.thymeleaf.expression.Temporals"),
			Map.entry("uris", "org.thymeleaf.expression.Uris"),
			Map.entry("fields", "org.thymeleaf.spring6.expression.Fields"),
			Map.entry("mvc", "org.thymeleaf.spring6.expression.Mvc"),
			Map.entry("themes", "org.thymeleaf.spring6.expression.Themes"));

	private final RuntimeHints hints = new RuntimeHints();

	@BeforeEach
	void registerHints() {
		new PetClinicRuntimeHints().registerHints(this.hints, getClass().getClassLoader());
	}

	@Test
	void thymeleafStringsListJoinIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection()
			.onMethodInvocation(Strings.class.getMethod("listJoin", List.class, String.class))).accepts(this.hints);
	}

	@Test
	void thymeleafNumbersSequenceIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection()
			.onMethodInvocation(Numbers.class.getMethod("sequence", Integer.class, Integer.class))).accepts(this.hints);
	}

	@Test
	void thymeleafTemporalsFormatIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection()
			.onMethodInvocation(Temporals.class.getMethod("format", Temporal.class, String.class))).accepts(this.hints);
	}

	@Test
	void thymeleafFieldsHasErrorsIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection()
			.onMethodInvocation(Fields.class.getMethod("hasErrors", String.class))).accepts(this.hints);
	}

	@Test
	void thymeleafFieldsAllErrorsIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection().onMethodInvocation(Fields.class.getMethod("allErrors")))
			.accepts(this.hints);
	}

	@Test
	void thymeleafFieldsHasAnyErrorsIsInvocable() throws NoSuchMethodException {
		assertThat(RuntimeHintsPredicates.reflection().onMethodInvocation(Fields.class.getMethod("hasAnyErrors")))
			.accepts(this.hints);
	}

	/**
	 * Scans every template for expression utility use such as
	 * {@code #strings.listJoin(...)} or {@code #execInfo.templateName} and checks that
	 * the method behind it is invocable in a native image. A new helper use without a
	 * hint then fails here instead of as an HTTP 500 in the native executable.
	 */
	@Test
	@DisabledInNativeImage
	void everyTemplateHelperUseIsInvocable() throws Exception {
		Resource[] templates = new PathMatchingResourcePatternResolver().getResources("classpath*:templates/**/*.html");
		assertThat(templates).as("templates on the classpath").isNotEmpty();
		// "helper.method()" for calls, "helper.property" for property access
		Set<String> uses = new TreeSet<>();
		for (Resource template : templates) {
			Matcher matcher = HELPER_USE.matcher(template.getContentAsString(StandardCharsets.UTF_8));
			while (matcher.find()) {
				boolean call = matcher.group(3) != null;
				// Without parentheses only known helpers count, so a CSS selector such as
				// #navbar.active is not taken for a helper.
				if (call || HELPER_CLASSES.containsKey(matcher.group(1))) {
					uses.add(matcher.group(1) + "." + matcher.group(2) + (call ? "()" : ""));
				}
			}
		}
		assertThat(uses).as("helper uses found in the templates").isNotEmpty();
		List<String> problems = new ArrayList<>();
		for (String use : uses) {
			String helper = use.substring(0, use.indexOf('.'));
			String member = use.substring(use.indexOf('.') + 1);
			String className = HELPER_CLASSES.get(helper);
			if (className == null) {
				problems.add("#" + use + ": unknown helper, add it to HELPER_CLASSES");
				continue;
			}
			// A call names the method. Property access goes through the getter.
			Set<String> methodNames = member.endsWith("()") ? Set.of(member.substring(0, member.length() - 2))
					: Set.of("get" + StringUtils.capitalize(member), "is" + StringUtils.capitalize(member));
			// The scan cannot tell which overload a template calls, so every public
			// overload must be invocable.
			List<Method> methods = Stream.of(Class.forName(className).getMethods())
				.filter((candidate) -> methodNames.contains(candidate.getName()))
				.toList();
			if (methods.isEmpty()) {
				problems.add("#" + use + ": " + className + " has no matching public method");
			}
			else if (!methods.stream()
				.allMatch(
						(method) -> RuntimeHintsPredicates.reflection().onMethodInvocation(method).test(this.hints))) {
				problems.add("#" + use + ": no reflection hint for " + className);
			}
		}
		assertThat(problems).as("template helper uses without a native reflection hint").isEmpty();
	}

}
