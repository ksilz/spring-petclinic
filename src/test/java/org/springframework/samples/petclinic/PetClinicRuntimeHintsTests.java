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
import org.thymeleaf.expression.Numbers;
import org.thymeleaf.expression.Strings;
import org.thymeleaf.expression.Temporals;
import org.thymeleaf.spring6.expression.Fields;

import org.springframework.aot.hint.RuntimeHints;
import org.springframework.aot.hint.predicate.RuntimeHintsPredicates;
import org.springframework.core.io.Resource;
import org.springframework.core.io.support.PathMatchingResourcePatternResolver;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Tests for {@link PetClinicRuntimeHints}.
 */
class PetClinicRuntimeHintsTests {

	private static final Pattern HELPER_CALL = Pattern.compile("#(\\w+)\\.(\\w+)\\s*\\(");

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
			Map.entry("mvc", "org.thymeleaf.spring6.expression.Mvc"));

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
	 * Scans every template for expression utility calls such as
	 * {@code #strings.listJoin(...)} and checks that each called method is invocable in a
	 * native image. A new helper call without a hint then fails here instead of as an
	 * HTTP 500 in the native executable.
	 */
	@Test
	void everyTemplateHelperCallIsInvocable() throws Exception {
		Resource[] templates = new PathMatchingResourcePatternResolver().getResources("classpath*:templates/**/*.html");
		assertThat(templates).as("templates on the classpath").isNotEmpty();
		Set<String> calls = new TreeSet<>();
		for (Resource template : templates) {
			Matcher matcher = HELPER_CALL.matcher(template.getContentAsString(StandardCharsets.UTF_8));
			while (matcher.find()) {
				calls.add(matcher.group(1) + "." + matcher.group(2));
			}
		}
		assertThat(calls).as("helper calls found in the templates").isNotEmpty();
		List<String> problems = new ArrayList<>();
		for (String call : calls) {
			String helper = call.substring(0, call.indexOf('.'));
			String method = call.substring(call.indexOf('.') + 1);
			String className = HELPER_CLASSES.get(helper);
			if (className == null) {
				problems.add("#" + call + ": unknown helper, add it to HELPER_CLASSES");
				continue;
			}
			// The scan cannot tell which overload a template calls, so every public
			// overload must be invocable.
			List<Method> overloads = Stream.of(Class.forName(className).getMethods())
				.filter((candidate) -> candidate.getName().equals(method))
				.toList();
			if (overloads.isEmpty()) {
				problems.add("#" + call + ": " + className + " has no public method " + method);
			}
			else if (!overloads.stream()
				.allMatch((overload) -> RuntimeHintsPredicates.reflection()
					.onMethodInvocation(overload)
					.test(this.hints))) {
				problems.add("#" + call + ": no reflection hint for " + className);
			}
		}
		assertThat(problems).as("template helper calls without a native reflection hint").isEmpty();
	}

}
